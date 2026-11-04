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

// Pairing is only accepted after `run.sh pair` opens it, and it closes with
// the first attempt: the PIN is six digits and nobody watches this process.
const _pairingWindow = Duration(minutes: 5);
const _defaultReadTimeout = Duration(seconds: 45);
const _replyTimeout = Duration(seconds: 12);

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
    // The secrets of the paired devices are in here: only this user's.
    if (!Platform.isWindows)
      await Process.run('chmod', ['700', directory.path]);
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

  // One write at a time: two requests at once would share the temporary file.
  var _writing = Future<void>.value();

  Future<void> _write(String fileName, Object value) {
    final text = jsonEncode(value);
    final done = _writing.then((_) async {
      final target = _file(fileName);
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', temporary.path]);
      }
      await temporary.rename(target.path);
    });
    // A failed write must not stop the next ones, but its caller sees it.
    _writing = done.then((_) {}, onError: (Object _) {});
    return done;
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
  _Peer(this.store, {this.readTimeout = _defaultReadTimeout});

  final _Store store;

  /// How long a request may take to send its body.
  final Duration readTimeout;

  // A large body is read by one request at a time: the others would pile up
  // to 64 MB each, and none of them has proven who sent it yet.
  var _largeBodyActive = false;
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

  // What a handler wants done once its reply went out, or failed to.
  final _afterReply = Expando<Future<void> Function(bool delivered)>();

  // Requests whose body was read to its end.
  final _bodyRead = Expando<bool>();

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
    // The clients always say so. A web page cannot send JSON to another
    // origin without a preflight request, which this server never answers.
    final (status, body) = handler == null
        ? (404, <String, dynamic>{'error': 'not_found'})
        : !_isJson(request)
        ? (415, <String, dynamic>{'error': 'unsupported_media_type'})
        : await handler(request);
    // A reply to a request whose body is large or of unknown size and was
    // not read would wait for all of it to arrive, and the sender decides
    // when that is: answer now and hang up instead.
    final length = request.contentLength;
    if (_bodyRead[request] != true &&
        (length < 0 || length > _smallMessageBytes)) {
      await _replyAndHangUp(request, status, body);
      return;
    }
    final afterReply = _afterReply[request];
    var delivered = true;
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      final closing = request.response.close();
      // A connection the other side reset never finishes writing: that only
      // matters when something depends on the reply having gone out.
      await (afterReply == null ? closing : closing.timeout(_replyTimeout));
    } catch (_) {
      // The other device gave up waiting.
      delivered = false;
    }
    if (afterReply != null) {
      try {
        await afterReply(delivered);
      } catch (e) {
        _log('Could not finish a request: $e');
      }
    }
  }

  Future<void> _replyAndHangUp(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = request.response..statusCode = status;
      final payload = utf8.encode(jsonEncode(body));
      final socket = await response.detachSocket(writeHeaders: false);
      socket
        ..add(
          utf8.encode(
            'HTTP/1.1 $status ${response.reasonPhrase}\r\n'
            'Content-Type: application/json; charset=utf-8\r\n'
            'Content-Length: ${payload.length}\r\n'
            'Connection: close\r\n\r\n',
          ),
        )
        ..add(payload);
      try {
        await socket.flush().timeout(_replyTimeout);
      } catch (_) {
        // The other device gave up waiting.
      }
      socket.destroy();
    } catch (_) {
      // The other device gave up waiting.
    }
  }

  bool _isJson(HttpRequest request) {
    try {
      return request.headers.contentType?.mimeType == 'application/json';
    } catch (_) {
      return false;
    }
  }

  /// Reads a request body, giving up after [readTimeout]. Unlike a timeout on
  /// the future, this stops listening, so a client that stalls or trickles
  /// cannot keep the read and its buffer alive.
  Future<Uint8List> _readBody(HttpRequest request, {required int maxBytes}) {
    final result = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);
    late final StreamSubscription<List<int>> subscription;
    void finish(void Function() complete) {
      if (result.isCompleted) return;
      complete();
      unawaited(subscription.cancel());
    }

    final timer = Timer(
      readTimeout,
      () => finish(
        () => result.completeError(const _Failure(408, 'request_timeout')),
      ),
    );
    subscription = request.listen(
      (chunk) {
        if (bytes.length + chunk.length > maxBytes) {
          finish(() => result.completeError(const _Failure(413, 'too_large')));
        } else {
          bytes.add(chunk);
        }
      },
      onDone: () => finish(() {
        _bodyRead[request] = true;
        result.complete(bytes.takeBytes());
      }),
      onError: (Object error, StackTrace stackTrace) =>
          finish(() => result.completeError(error, stackTrace)),
      cancelOnError: true,
    );
    return result.future.whenComplete(timer.cancel);
  }

  Future<Map<String, dynamic>> _readJson(
    HttpRequest request, {
    required int maxBytes,
  }) async {
    final bytes = await _readBody(request, maxBytes: maxBytes);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const _Failure(400, 'invalid');
    return Map<String, dynamic>.from(decoded);
  }

  File get _windowFile => File('${store.directory.path}/pairing-open');

  bool get _pairingOpen {
    final file = _windowFile;
    return file.existsSync() &&
        DateTime.now().difference(file.lastModifiedSync()) < _pairingWindow;
  }

  void _closePairingWindow() {
    try {
      final file = _windowFile;
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException catch (e) {
      _log('Could not close the pairing window: $e');
    }
  }

  DateTime? _lastRefusalLogged;

  void _clearPairing() {
    _pendingTimer?.cancel();
    _pendingSession = null;
    _pendingClientId = null;
    _pendingClientName = null;
    _pendingPairing = null;
    _pendingTimer = null;
    try {
      final pin = File('${store.directory.path}/pairing-pin.txt');
      if (pin.existsSync()) pin.deleteSync();
    } on FileSystemException catch (e) {
      _log('Could not remove the PIN file: $e');
    }
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
      if (!_pairingOpen) {
        final now = DateTime.now();
        if (_lastRefusalLogged == null ||
            now.difference(_lastRefusalLogged!) > const Duration(minutes: 1)) {
          _lastRefusalLogged = now;
          _log('Pairing refused: not open (run.sh pair opens it)');
        }
        return (403, {'error': 'pairing_closed'});
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
    final ({String secret, String proof}) agreement;
    try {
      agreement = await pairing.verify(data['proof']);
    } catch (_) {
      // Only a proof that fails is a wrong PIN.
      _closePairingWindow();
      _clearPairing();
      _log('Pairing failed: wrong PIN; pairing is closed');
      return (403, {'error': 'incorrect_pin'});
    }
    if (_pendingSession != session) {
      return (403, {'error': 'pairing_cancelled'});
    }
    final id = _pendingClientId!;
    final clientName = _pendingClientName!;
    final previous = store.paired[id];
    final counters = {
      for (final e in store.counters.entries)
        if (e.key.contains(':$id:')) e.key: e.value,
    };
    // Puts the trust of [id] back as it was.
    Future<void> undo() async {
      if (previous == null) {
        store.paired.remove(id);
      } else {
        store.paired[id] = previous;
      }
      store.counters
        ..removeWhere((key, _) => key.contains(':$id:'))
        ..addAll(counters);
      await store.saveState();
    }

    try {
      final confirmation = await SyncSecurity.seal(agreement.secret, {
        'status': 'paired',
        'deviceId': store.deviceId,
        'deviceName': store.name,
      }, 'pair:$session:reply');
      store.paired[id] = (name: clientName, secret: agreement.secret);
      // Replay counters belong to the secret they were made with.
      final digest = syncDigest(agreement.secret);
      store.counters.removeWhere(
        (key, _) => key.contains(':$id:') && !key.endsWith(digest),
      );
      await store.saveState();
      _log('Paired with "$clientName" ($id)');
      _closePairingWindow();
      _clearPairing();
      // The peer trusts the other device now: if the reply never reaches it,
      // the other one does not trust the peer, so that is undone.
      _afterReply[request] = (delivered) async {
        if (delivered) return;
        _log('The confirmation of "$clientName" did not arrive; undone');
        await undo();
      };
      return (200, {'proof': agreement.proof, 'confirmation': confirmation});
    } catch (e) {
      // The PIN was right; the peer failed. Not a wrong PIN, and not paired:
      // the pairing stays open for another try.
      _log('Pairing could not be completed: $e');
      _clearPairing();
      try {
        await undo();
      } catch (e) {
        _log('Could not undo an unfinished pairing: $e');
      }
      return (500, {'error': 'pairing_failed'});
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
    final large = maxBytes > _smallMessageBytes;
    if (large) {
      // The device id is public (discovery answers with it), so a large body
      // is not trusted yet: its size must be known, and only one is read.
      if (request.contentLength < 0)
        throw const _Failure(411, 'length_required');
      if (_largeBodyActive) throw const _Failure(429, 'busy');
      _largeBodyActive = true;
    }
    final Map<String, dynamic> body;
    try {
      final bytes = await _readBody(request, maxBytes: maxBytes);
      body = await SyncSecurity.openRequestInBackground(
        peer.secret,
        bytes,
        '${request.uri.path.substring(1)}|$id|${store.deviceId}',
        apiVersion: _apiVersion,
      );
    } on SyncEnvelopeException catch (e) {
      throw e.upgradeRequired
          ? const _Failure(426, 'upgrade_required')
          : const _Failure(400, 'invalid');
    } on SyncTooLargeException {
      throw const _Failure(413, 'too_large');
    } on FormatException {
      throw const _Failure(400, 'invalid');
    } on _Failure {
      rethrow;
    } catch (_) {
      // A wrong secret fails the authentication of the message.
      throw const _Failure(403, 'not_paired');
    } finally {
      if (large) _largeBodyActive = false;
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
  var readTimeout = _defaultReadTimeout;
  var list = false;
  String? unpair;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--data':
        data = arguments[++i];
      case '--name':
        name = arguments[++i];
      case '--port':
        port = int.parse(arguments[++i]);
      case '--read-timeout':
        readTimeout = Duration(seconds: int.parse(arguments[++i]));
      case '--list':
        list = true;
      case '--unpair':
        unpair = arguments[++i];
      default:
        stderr.writeln(
          'Usage: zenify_sync_peer [--data DIR] [--name NAME] [--port PORT]\n'
          '                        [--read-timeout SECONDS]\n'
          '       zenify_sync_peer [--data DIR] --list | --unpair ID',
        );
        exit(64);
    }
  }
  final store = _Store(Directory(data));
  await store.load(name);
  if (list || unpair != null) {
    // Offline commands: the peer must not be running, it keeps these in memory.
    if (unpair != null) {
      if (store.paired.remove(unpair) == null) {
        stderr.writeln('No paired device with that id.');
        exit(1);
      }
      store.counters.removeWhere((key, _) => key.contains(':$unpair:'));
      await store.saveState();
      stdout.writeln('Unpaired $unpair.');
    }
    for (final entry in store.paired.entries) {
      stdout.writeln('${entry.key}  ${entry.value.name}');
    }
    return;
  }
  await _Peer(store, readTimeout: readTimeout).start(port);
}
