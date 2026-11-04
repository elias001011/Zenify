import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/local_sync/sync_pairing.dart';
import 'package:musify/services/local_sync/sync_security.dart';

import 'fixtures.dart';
import 'raw_http.dart';

/// The server half of the headless peer (tools/sync_peer), started as the
/// program it is and spoken to over HTTP as the apps speak to it.
///
/// By default a peer is started on this machine. To check one that is already
/// running (on a server, with a data folder made for the check) give its
/// address and a paired device that the check may use:
///   MUSIFY_PEER_HOST, MUSIFY_PEER_PORT, MUSIFY_PEER_ID (the peer's own id),
///   MUSIFY_PEER_CLIENT (the paired device's id), MUSIFY_PEER_SECRET and
///   MUSIFY_PEER_READ_TIMEOUT (its --read-timeout, in seconds).
void main() {
  final env = Platform.environment;
  final remote = env['MUSIFY_PEER_HOST'] != null;
  const client = 'check-device';
  const peerId = 'peer-under-test';
  final secret = SyncSecurity.randomToken();
  late Directory data;
  late Process process;
  final log = StringBuffer();
  late String host;
  late int port;
  late String peerDeviceId;
  late String clientId;
  late String pairedSecret;
  var readTimeout = 2;
  var sequence = 0;
  final dartAvailable = Process.runSync('dart', ['--version']).exitCode == 0;

  setUpAll(() async {
    if (remote) {
      host = env['MUSIFY_PEER_HOST']!;
      port = int.parse(env['MUSIFY_PEER_PORT']!);
      peerDeviceId = env['MUSIFY_PEER_ID']!;
      clientId = env['MUSIFY_PEER_CLIENT']!;
      pairedSecret = env['MUSIFY_PEER_SECRET']!;
      readTimeout = int.parse(env['MUSIFY_PEER_READ_TIMEOUT'] ?? '45');
      return;
    }
    host = '127.0.0.1';
    peerDeviceId = peerId;
    clientId = client;
    pairedSecret = secret;
    final get = Process.runSync('dart', [
      'pub',
      'get',
    ], workingDirectory: 'tools/sync_peer');
    expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    data = await Directory.systemTemp.createTemp('musify_peer_check');
    File('${data.path}/state.json').writeAsStringSync(
      jsonEncode({
        'deviceId': peerId,
        'name': 'Peer under test',
        'paired': {
          client: {'name': 'Check', 'secret': secret},
        },
        'counters': <String, int>{},
      }),
    );
    process = await Process.start('dart', [
      'run',
      'bin/zenify_sync_peer.dart',
      '--data',
      data.path,
      '--port',
      '0',
      '--read-timeout',
      '$readTimeout',
    ], workingDirectory: 'tools/sync_peer');
    final started = Completer<int>();
    process.stdout.transform(utf8.decoder).listen((text) {
      log.write(text);
      final match = RegExp(r'on port (\d+)').firstMatch(log.toString());
      if (match != null && !started.isCompleted) {
        started.complete(int.parse(match.group(1)!));
      }
    });
    process.stderr.transform(utf8.decoder).listen(log.write);
    port = await started.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw StateError('The peer did not start: $log'),
    );
  });
  tearDown(() => printOnFailure(log.toString()));
  tearDownAll(() async {
    if (remote) return;
    process.kill();
    await process.exitCode;
    await data.delete(recursive: true);
  });

  Future<RawHttp> connect() async => RawHttp(await Socket.connect(host, port));

  Future<Map<String, dynamic>> envelope(
    String path,
    Map<String, dynamic> body,
  ) async => {
    'apiVersion': 3,
    'encrypted': await SyncSecurity.seal(pairedSecret, {
      ...body,
      'requestId': SyncSecurity.randomToken(24),
      'sequence': DateTime.now().microsecondsSinceEpoch + sequence++,
    }, 'api/sync/$path|$clientId|$peerDeviceId'),
  };

  /// A request the way the apps send it: a JSON body with its length.
  Future<({int status, String body})> send(
    String path,
    List<int> body, {
    String? device,
    String? contentType = 'application/json',
  }) async {
    final raw = await connect();
    raw.socket
      ..add(
        utf8.encode(
          rawHead(
            path,
            device: device ?? clientId,
            contentType: contentType,
            length: body.length,
          ),
        ),
      )
      ..add(body);
    final status = await raw.awaitStatus();
    // The body follows the status line in the same read, or just after.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reply = raw.body;
    raw.socket.destroy();
    return (status: status, body: reply);
  }

  final notAnEnvelope = utf8.encode('{"apiVersion":3}');
  final skip = !remote && !dartAvailable ? 'dart is not on the PATH' : null;

  test('every route refuses what is not JSON', () async {
    for (final path in [
      'pair-request',
      'pair-verify',
      'capabilities',
      'merge',
    ]) {
      expect(
        (await send(path, notAnEnvelope, contentType: 'text/plain')).status,
        415,
        reason: path,
      );
      expect(
        (await send(path, notAnEnvelope, contentType: null)).status,
        415,
        reason: '$path without a type',
      );
    }
  }, skip: skip);

  test(
    'an envelope it cannot open is refused, a stranger turned away',
    () async {
      expect((await send('merge', notAnEnvelope)).status, 400);
      expect(
        (await send('merge', notAnEnvelope, device: 'stranger')).status,
        403,
      );
      expect(
        (await send('merge', utf8.encode('{"apiVersion":2}'))).status,
        426,
      );
    },
    skip: skip,
  );

  test('a merge without a length is refused before it is read', () async {
    final raw = await connect();
    raw.socket
      ..add(utf8.encode(rawHead('merge', device: clientId, chunked: true)))
      ..add(utf8.encode('${notAnEnvelope.length.toRadixString(16)}\r\n'))
      ..add(notAnEnvelope)
      ..add(utf8.encode('\r\n0\r\n\r\n'));
    expect(await raw.awaitStatus(), 411);
  }, skip: skip);

  test('a declared length over the limit is refused unread', () async {
    final raw = await connect();
    raw.socket.add(
      utf8.encode(rawHead('merge', device: clientId, length: 70 * 1024 * 1024)),
    );
    expect(await raw.awaitStatus(), 413);
    expect(await raw.awaitClosed(), true);
  }, skip: skip);

  test('a body that stalls is dropped at the timeout', () async {
    final slow = await connect();
    slow.socket
      ..add(utf8.encode(rawHead('merge', device: clientId, length: 5000)))
      ..add(Uint8List(100));
    final started = DateTime.now();
    expect(await slow.awaitStatus(Duration(seconds: readTimeout + 10)), 408);
    final took = DateTime.now().difference(started).inMilliseconds;
    expect(took, greaterThan((readTimeout - 1) * 1000));
    expect(took, lessThan((readTimeout + 5) * 1000));
    expect(await slow.awaitClosed(), true);
    // Nothing is held: the next one is read.
    expect((await send('merge', notAnEnvelope)).status, 400);
  }, skip: skip);

  test('only one large body is read at a time', () async {
    final first = await connect();
    first.socket
      ..add(utf8.encode(rawHead('merge', device: clientId, length: 1000)))
      ..add(Uint8List(10));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect((await send('merge', notAnEnvelope)).status, 429);
    first.socket.destroy();
  }, skip: skip);

  test('a merge as the apps send it still works', () async {
    final library = payload(
      document({
        'likedSongs': [song('peer-check-$clientId')],
      }),
    );
    final body = utf8.encode(
      jsonEncode(
        await envelope('merge', {
          'categories': library['categories'],
          'library': library,
        }),
      ),
    );
    final result = await send('merge', body);
    expect(result.status, 200, reason: result.body);
    final reply = jsonDecode(result.body) as Map;
    final clear = await SyncSecurity.open(
      pairedSecret,
      reply['encrypted'],
      'api/sync/merge|$peerDeviceId|$clientId',
    );
    expect(
      (clear['library']['document']['records'] as Map).keys.join(),
      contains('peer-check-$clientId'),
    );
  }, skip: skip);

  test('a record that names a path outside the library is refused', () async {
    for (final id in ['../../x', 'a/b', r'a\b', 'tab\there', 'x' * 129]) {
      final library = payload(
        document({
          'likedSongs': [song('fine')],
        }),
      );
      final records = Map<String, dynamic>.from(
        library['document']['records'] as Map,
      );
      final key = records.keys.firstWhere((k) => k.contains('fine'));
      final cell = Map<String, dynamic>.from(records.remove(key) as Map);
      cell['value'] = {...cell['value'] as Map, 'ytid': id};
      records[jsonEncode(['likedSongs', '', id])] = cell;
      library['document']['records'] = records;
      final body = utf8.encode(
        jsonEncode(
          await envelope('merge', {
            'categories': library['categories'],
            'library': library,
          }),
        ),
      );
      final result = await send('merge', body);
      expect(result.status, 400, reason: 'id ${jsonEncode(id)}');
    }
  }, skip: skip);

  test(
    'a storage failure after the right PIN is not a wrong PIN',
    () async {
      final window = File('${data.path}/pairing-open')..writeAsStringSync('');
      final pinFile = File('${data.path}/pairing-pin.txt');
      Future<({String session, PinPairingClient pairing})> request() async {
        final response = await send(
          'pair-request',
          utf8.encode(
            jsonEncode({
              'apiVersion': 3,
              'clientId': 'newcomer',
              'clientName': 'Newcomer',
            }),
          ),
          device: 'none',
        );
        expect(response.status, 200, reason: response.body);
        final reply = jsonDecode(response.body) as Map;
        final session = reply['session'] as String;
        final pairing = await PinPairingClient.create(
          reply['challenge'],
          'newcomer|$peerDeviceId|$session',
          pinFile.readAsStringSync().trim(),
        );
        return (session: session, pairing: pairing);
      }

      Future<int> verify(
        ({String session, PinPairingClient pairing}) attempt,
      ) async => (await send(
        'pair-verify',
        utf8.encode(
          jsonEncode({
            'session': attempt.session,
            'proof': attempt.pairing.proof(),
          }),
        ),
        device: 'none',
      )).status;

      final failing = await request();
      // The folder can no longer be written to: the peer fails, not the PIN.
      Process.runSync('chmod', ['500', data.path]);
      try {
        expect(await verify(failing), 500);
      } finally {
        Process.runSync('chmod', ['700', data.path]);
      }
      expect(window.existsSync(), true, reason: 'the window stays open');
      final state = jsonDecode(
        File('${data.path}/state.json').readAsStringSync(),
      );
      expect((state['paired'] as Map).keys, isNot(contains('newcomer')));

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(await verify(await request()), 200);
      final paired = jsonDecode(
        File('${data.path}/state.json').readAsStringSync(),
      );
      expect((paired['paired'] as Map).keys, contains('newcomer'));
      expect(window.existsSync(), false, reason: 'closed by the pairing');
    },
    skip: remote
        ? 'needs the data folder of the peer'
        : Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
        ? 'root writes anywhere'
        : skip,
  );
}
