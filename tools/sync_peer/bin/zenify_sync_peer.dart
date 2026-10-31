// A Zenify device with no screen: it takes part in Local Sync, keeps what the
// others sync and gives it back, so a phone and a computer that are never on
// at the same time still end up with the same library. It speaks the app's
// own protocol with the app's own code (lib/services/local_sync, shared with
// the app), so nothing in the app changes.
//
//   dart run bin/zenify_sync_peer.dart --data ~/zenify-sync/data
//
// Pairing: start the peer, pair from the app as with any device, and read the
// PIN from this program's output (or from `pairing-pin.txt` in the data
// folder) instead of from a screen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:musify/services/local_sync/sync_data.dart';
import 'package:musify/services/local_sync/sync_merge.dart';
import 'package:musify/services/local_sync/sync_pairing.dart';
import 'package:musify/services/local_sync/sync_security.dart';

const _discoveryPort = 53531;
const _apiVersion = 3;
const _smallMessageBytes = 64 * 1024;
const _deviceHeader = 'x-musify-device';
const _discoveryRequest = 'MUSIFY_DISCOVERY_REQUEST';
const _discoveryResponse = 'MUSIFY_DISCOVERY_RESPONSE';
const _pairingTimeout = Duration(seconds: 60);
const _readTimeout = Duration(seconds: 45);

typedef _Reply = (int, Map<String, dynamic>);

class _Failure implements Exception {
  const _Failure(this.status, this.code);
  final int status;
  final String code;
}

void _log(String message) =>
    stdout.writeln('[${DateTime.now().toIso8601String()}] $message');

/// What the peer keeps: who it is, who it trusts, and the library.
class _Store {
  _Store(this.directory);

  final Directory directory;
  late String deviceId;
  late String name;
  final paired = <String, ({String name, String secret})>{};
  final counters = <String, int>{};
  var document = SyncDocument();

  File _file(String name) => File('${directory.path}/$name');

  Future<void> load(String defaultName) async {
    await directory.create(recursive: true);
    final state = _file('state.json');
    if (await state.exists()) {
      final raw = jsonDecode(await state.readAsString()) as Map;
      deviceId = raw['deviceId'] as String;
      name = raw['name'] as String? ?? defaultName;
      for (final entry in (raw['paired'] as Map? ?? {}).entries) {
        final device = entry.value as Map;
        paired[entry.key as String] = (
          name: device['name'] as String,
          secret: device['secret'] as String,
        );
      }
      for (final entry in (raw['counters'] as Map? ?? {}).entries) {
        counters[entry.key as String] = entry.value as int;
      }
    } else {
      final random = Random.secure();
      deviceId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      name = defaultName;
      await saveState();
    }
    final library = _file('document.json');
    if (await library.exists()) {
      document = SyncDocument.fromMap(
        jsonDecode(await library.readAsString()) as Map,
      );
    }
  }

  Future<void> _write(String fileName, Object value) async {
    final target = _file(fileName);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(target.path);
    if (!Platform.isWindows) await Process.run('chmod', ['600', target.path]);
  }

  Future<void> saveState() => _write('state.json', {
    'deviceId': deviceId,
    'name': name,
    'paired': {
      for (final e in paired.entries)
        e.key: {'name': e.value.name, 'secret': e.value.secret},
    },
    'counters': counters,
  });

  Future<void> saveDocument() => _write('document.json', document.toMap());
}

class _Peer {
  _Peer(this.store);

  final _Store store;
  late HttpServer _server;
  RawDatagramSocket? _udp;
  var _merging = Future<void>.value();

  // One pairing at a time, as in the app.
  String? _pendingSession;
  String? _pendingClientId;
  String? _pendingClientName;
  PinPairingReceiver? _pendingPairing;
  Timer? _pendingTimer;
  DateTime? _lastPairingRequest;

  Future<void> start(int port) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server.listen((request) => unawaited(_handle(request)));
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
      );
      _udp!.listen(_onDatagram);
    } on SocketException catch (e) {
      _log('Discovery port $_discoveryPort is not available: $e');
    }
    _log(
      'Zenify sync peer "${store.name}" (${store.deviceId}) on port '
      '${_server.port}, ${store.paired.length} paired device(s)',
    );
  }

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _udp?.receive();
    if (datagram == null) return;
    String message;
    try {
      message = utf8.decode(datagram.data);
    } on FormatException {
      return;
    }
    if (message != _discoveryRequest) return;
    final response =
        '$_discoveryResponse;${store.name.replaceAll(';', ' ')};'
        '${_server.port};${store.deviceId}';
    _udp?.send(utf8.encode(response), datagram.address, datagram.port);
  }

  Future<void> _handle(HttpRequest request) async {
    final handler = request.method != 'POST'
        ? null
        : switch (request.uri.path) {
            '/api/sync/pair-request' => _pairRequest,
            '/api/sync/pair-verify' => _pairVerify,
            '/api/sync/capabilities' => _capabilities,
            '/api/sync/merge' => _merge,
            _ => null,
          };
    final (status, body) = handler == null
        ? (404, <String, dynamic>{'error': 'not_found'})
        : await handler(request);
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    } catch (_) {
      // The other device gave up waiting.
    }
  }

  Future<Uint8List> _readMessage(
    Stream<List<int>> stream, {
    required int maxBytes,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const _Failure(413, 'too_large');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<Map<String, dynamic>> _readJson(
    HttpRequest request, {
    required int maxBytes,
  }) async {
    final bytes = await _readMessage(
      request,
      maxBytes: maxBytes,
    ).timeout(_readTimeout);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const _Failure(400, 'invalid');
    return Map<String, dynamic>.from(decoded);
  }

  void _clearPairing() {
    _pendingTimer?.cancel();
    _pendingSession = null;
    _pendingClientId = null;
    _pendingClientName = null;
    _pendingPairing = null;
    _pendingTimer = null;
    final pin = File('${store.directory.path}/pairing-pin.txt');
    if (pin.existsSync()) pin.deleteSync();
  }

  Future<_Reply> _pairRequest(HttpRequest request) async {
    final Map<String, dynamic> data;
    try {
      data = await _readJson(request, maxBytes: _smallMessageBytes);
    } catch (_) {
      return (400, {'error': 'invalid_pairing'});
    }
    try {
      if (data['apiVersion'] != _apiVersion) {
        return (426, {'error': 'upgrade_required'});
      }
      final id = data['clientId'];
      if (id is! String || id.isEmpty || id.length > 128) {
        return (400, {'error': 'invalid_pairing'});
      }
      final now = DateTime.now();
      if (_pendingSession != null ||
          (_lastPairingRequest != null &&
              now.difference(_lastPairingRequest!) <
                  const Duration(seconds: 3))) {
        return (429, {'error': 'pairing_busy'});
      }
      _lastPairingRequest = now;
      _pendingClientId = id;
      final name = data['clientName']?.toString() ?? 'Zenify';
      _pendingClientName = name.substring(0, min(100, name.length));
      final session = SyncSecurity.randomToken(16);
      _pendingSession = session;
      _pendingTimer = Timer(_pairingTimeout, _clearPairing);
      final pairing = await PinPairingReceiver.create(
        '$id|${store.deviceId}|$session',
      );
      if (_pendingSession != session) {
        return (403, {'error': 'pairing_expired'});
      }
      _pendingPairing = pairing;
      // No screen: the PIN is for whoever reads this output or the file.
      _log('PAIRING with "$_pendingClientName": PIN ${pairing.pin} (60 s)');
      final file = File('${store.directory.path}/pairing-pin.txt');
      await file.writeAsString('${pairing.pin}\n', flush: true);
      return (
        200,
        {
          'session': session,
          'challenge': pairing.challenge,
          'deviceId': store.deviceId,
        },
      );
    } catch (_) {
      _clearPairing();
      return (400, {'error': 'invalid_pairing'});
    }
  }

  Future<_Reply> _pairVerify(HttpRequest request) async {
    final Map<String, dynamic> data;
    try {
      data = await _readJson(request, maxBytes: _smallMessageBytes);
    } catch (_) {
      return (400, {'error': 'invalid_pairing'});
    }
    final session = _pendingSession;
    final pairing = _pendingPairing;
    // Only the requester knows the session, so other hosts cannot cancel it.
    if (session == null ||
        pairing == null ||
        data['session'] != session ||
        data['proof'] is! Map) {
      return (403, {'error': 'pairing_expired'});
    }
    try {
      final agreement = await pairing.verify(data['proof']);
      if (_pendingSession != session) {
        return (403, {'error': 'pairing_cancelled'});
      }
      final id = _pendingClientId!;
      store.paired[id] = (name: _pendingClientName!, secret: agreement.secret);
      // Replay counters belong to the secret they were made with.
      final digest = syncDigest(agreement.secret);
      store.counters.removeWhere(
        (key, _) => key.contains(':$id:') && !key.endsWith(digest),
      );
      await store.saveState();
      final confirmation = await SyncSecurity.seal(agreement.secret, {
        'status': 'paired',
        'deviceId': store.deviceId,
        'deviceName': store.name,
      }, 'pair:$session:reply');
      _log('Paired with "$_pendingClientName" ($id)');
      _clearPairing();
      return (200, {'proof': agreement.proof, 'confirmation': confirmation});
    } catch (_) {
      _clearPairing();
      return (403, {'error': 'incorrect_pin'});
    }
  }

  Future<({Map<String, dynamic> body, String peerId})> _authenticated(
    HttpRequest request, {
    int maxBytes = maxSyncMessageBytes,
  }) async {
    final id = request.headers.value(_deviceHeader);
    if (id == null) throw const _Failure(426, 'upgrade_required');
    final peer = store.paired[id];
    if (peer == null) throw const _Failure(403, 'not_paired');
    if (request.contentLength > maxBytes) {
      throw const _Failure(413, 'too_large');
    }
    final data = await _readJson(request, maxBytes: maxBytes);
    if (data['apiVersion'] != _apiVersion) {
      throw const _Failure(426, 'upgrade_required');
    }
    if (data['encrypted'] is! Map) throw const _Failure(400, 'invalid');
    final Map<String, dynamic> body;
    try {
      body = await SyncSecurity.open(
        peer.secret,
        data['encrypted'],
        '${request.uri.path.substring(1)}|$id|${store.deviceId}',
      );
    } on SyncTooLargeException {
      throw const _Failure(413, 'too_large');
    } on FormatException {
      throw const _Failure(400, 'invalid');
    } catch (_) {
      // A wrong secret fails the authentication of the message.
      throw const _Failure(403, 'not_paired');
    }
    final nonce = body['requestId'];
    if (nonce is! String || nonce.length < 20 || nonce.length > 128) {
      throw const _Failure(400, 'invalid_request');
    }
    final counterKey = 'localSyncReceived:$id:${syncDigest(peer.secret)}';
    final sequence = body['sequence'];
    if (sequence is! int || sequence <= (store.counters[counterKey] ?? 0)) {
      throw const _Failure(403, 'replayed_request');
    }
    store.counters[counterKey] = sequence;
    await store.saveState();
    return (body: body, peerId: id);
  }

  Future<_Reply> _encryptedReply(
    HttpRequest request,
    String peerId,
    Map<String, dynamic> received,
    Map<String, dynamic> body,
  ) async {
    final context =
        '${request.uri.path.substring(1)}|${store.deviceId}|$peerId';
    return (
      200,
      {
        'encrypted': await SyncSecurity.seal(store.paired[peerId]!.secret, {
          ...body,
          'requestId': received['requestId'],
        }, context),
      },
    );
  }

  Future<_Reply> _capabilities(HttpRequest request) async {
    try {
      final auth = await _authenticated(request, maxBytes: _smallMessageBytes);
      return await _encryptedReply(request, auth.peerId, auth.body, {
        'schemaVersion': syncSchemaVersion,
        'categories': [
          for (final c in SyncCategory.values)
            if (!zenifyOnlySyncCategories.contains(c)) c.name,
        ],
        'zenifyCategories': [for (final c in zenifyOnlySyncCategories) c.name],
      });
    } on _Failure catch (e) {
      return (e.status, {'error': e.code});
    } catch (_) {
      return (400, {'error': 'invalid_request'});
    }
  }

  Future<_Reply> _merge(HttpRequest request) async {
    try {
      final auth = await _authenticated(request);
      final categories = parseSyncCategories(auth.body['categories']);
      if (categories.isEmpty) return (409, {'error': 'categories_changed'});
      final library = auth.body['library'];
      if (library is! Map) return (400, {'error': 'library_missing'});
      if (library['schemaVersion'] != syncSchemaVersion ||
          library['document'] is! Map ||
          library['document']['version'] != syncSchemaVersion) {
        return (426, {'error': 'upgrade_required'});
      }
      final incomingCategories = parseSyncCategories(library['categories']);
      if (!categories.containsAll(incomingCategories)) {
        return (409, {'error': 'categories_changed'});
      }
      final incoming = SyncDocument.fromMap(library['document']);
      if (incoming.select(incomingCategories).records.length !=
          incoming.records.length) {
        return (400, {'error': 'invalid'});
      }

      // One merge at a time: each reads the library the last one wrote.
      final done = Completer<void>();
      final previous = _merging;
      _merging = done.future;
      await previous;
      try {
        final changes = store.document.join(incoming);
        if (changes > 0) await store.saveDocument();
        _log(
          'Synced with "${store.paired[auth.peerId]!.name}": '
          '$changes change(s), ${store.document.records.length} records',
        );
        return await _encryptedReply(request, auth.peerId, auth.body, {
          'library': {
            'schemaVersion': syncSchemaVersion,
            'categories': incomingCategories.map((e) => e.name).toList()
              ..sort(),
            'document': store.document.select(incomingCategories).toMap(),
          },
          // What changed here is not told: nothing shows it on this side.
          'changed': changes > 0 ? ['_metadata'] : <String>[],
        });
      } finally {
        done.complete();
      }
    } on _Failure catch (e) {
      return (e.status, {'error': e.code});
    } on FormatException {
      return (400, {'error': 'invalid'});
    } catch (e) {
      _log('Merge failed: $e');
      return (400, {'error': 'invalid_request'});
    }
  }
}

Future<void> main(List<String> arguments) async {
  var data = '${Platform.environment['HOME'] ?? '.'}/zenify-sync/data';
  var name = 'Zenify Sync Server';
  var port = 0;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--data':
        data = arguments[++i];
      case '--name':
        name = arguments[++i];
      case '--port':
        port = int.parse(arguments[++i]);
      default:
        stderr.writeln(
          'Usage: zenify_sync_peer [--data DIR] [--name NAME] [--port PORT]',
        );
        exit(64);
    }
  }
  final store = _Store(Directory(data));
  await store.load(name);
  await _Peer(store).start(port);
}
