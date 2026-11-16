import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/local_sync/sync_security.dart';
import 'package:musify/services/local_sync_service.dart';

import 'service_harness.dart';

void main() {
  final harness = SyncHarness();
  setUpAll(harness.openStorage);
  tearDownAll(harness.closeStorage);
  setUp(harness.start);
  tearDown(() => harness.server.dispose());

  Future<List<String>> listen(HttpServer server) async {
    final hits = <String>[];
    server.listen((request) async {
      hits.add('${request.method} ${request.uri}');
      await request.drain<void>();
      await request.response.close();
    });
    return hits;
  }

  test('a redirect from a peer is not followed', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hits = await listen(target);
    final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fake.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set('location', 'http://127.0.0.1:${target.port}/admin');
      await request.response.close();
    });
    addTearDown(() => target.close(force: true));
    addTearDown(() => fake.close(force: true));

    await harness.server.syncWith(
      DiscoveredSyncDevice(
        ip: '127.0.0.1',
        port: fake.port,
        name: 'Fixture',
        deviceId: SyncHarness.peerId,
      ),
    );

    expect(harness.server.state.value.status, LocalSyncStatus.error);
    expect(hits, isEmpty);
  });

  test('an address outside the local network is never contacted', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hits = await listen(target);
    addTearDown(() => target.close(force: true));
    final service = LocalSyncService.forTesting(allowLoopbackPeers: false);
    addTearDown(service.dispose);
    await service.startServer();
    await service.savePairedDevice(
      PairedSyncDevice(
        deviceId: 'phone',
        name: 'Phone',
        secret: SyncSecurity.randomToken(),
      ),
    );

    await service.syncWith(
      DiscoveredSyncDevice(
        ip: '127.0.0.1',
        port: target.port,
        name: 'Phone',
        deviceId: 'phone',
      ),
    );

    expect(service.state.value.error, LocalSyncError.unreachable);
    expect(hits, isEmpty);
  });

  test('a flood of answers is capped and a paired device still fits', () async {
    final responder = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      LocalSyncService.discoveryPort,
    );
    addTearDown(responder.close);
    var answered = false;
    responder.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final request = responder.receive();
      if (request == null || answered) return;
      if (utf8.decode(request.data, allowMalformed: true) !=
          'MUSIFY_DISCOVERY_REQUEST') {
        return;
      }
      answered = true;
      void answer(String name, String id) => responder.send(
        utf8.encode('MUSIFY_DISCOVERY_RESPONSE;$name;40000;$id'),
        request.address,
        request.port,
      );
      for (var i = 0; i < 50; i++) {
        answer('Fake $i', 'fake-$i');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      answer('x' * 600, 'oversized');
      answer('Fixture', SyncHarness.peerId);
    });

    final found = await harness.server.discoverDevices(
      duration: const Duration(seconds: 1),
    );
    final ids = found.map((device) => device.deviceId).toList();

    expect(ids, contains(SyncHarness.peerId));
    expect(ids, isNot(contains('oversized')));
    expect(ids.where((id) => id.startsWith('fake-')).length, lessThan(3));
  });
}
