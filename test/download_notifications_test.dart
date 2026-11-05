import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/localization/app_localizations_en.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/download_notifications.dart';

import 'support/app_harness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zenify/downloads');
  final manager = DownloadManager.instance;
  late DownloadNotifications notifications;
  final calls = <MethodCall>[];
  var permissionGranted = true;
  var startRefused = false;
  var openedByTap = false;
  var opened = 0;

  Iterable<MethodCall> sent(String method) =>
      calls.where((call) => call.method == method);

  Map<Object?, Object?> argumentsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  Map<String, dynamic> song(String id) => {'ytid': id, 'title': id};

  // The native side, as far as Dart can tell.
  Future<Object?> native(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'start':
        if (startRefused) {
          throw PlatformException(code: 'service_not_started');
        }
      case 'hasNotificationPermission':
        return permissionGranted;
      case 'requestNotificationPermission':
        return true;
      case 'takeOpenRequest':
        return openedByTap;
    }
    return null;
  }

  useAppSettings(boxes: ['userNoBackup']);

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    permissionGranted = true;
    startRefused = false;
    openedByTap = false;
    opened = 0;
    await Hive.box('userNoBackup').clear();
    manager
      ..idleMargin = const Duration(milliseconds: 150)
      ..reset();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, native);
    notifications = DownloadNotifications(
      manager,
      strings: AppLocalizationsEn.new,
    )..updateInterval = const Duration(milliseconds: 30);
  });

  tearDown(() async {
    // Lets what is still running end before the next test resets it.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    notifications.detach();
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> attach() async {
    notifications.attach(openDownloads: () => opened++);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> settle(DownloadEntry entry, {bool fail = false}) async {
    fail ? manager.failed(entry, StateError('x')) : manager.finished(entry);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'the service starts with the first download and stops when idle',
    () async {
      await attach();
      expect(sent('start'), isEmpty);

      final entry = manager.started(song('a'));
      await Future<void>.delayed(Duration.zero);
      final start = argumentsOf(sent('start').single);
      expect(start['title'], 'Downloading songs');
      expect(start['text'], '0 of 1 downloaded');
      expect(start['max'], 1);
      expect(start['current'], 0);
      expect(start['channelName'], 'Downloads');

      await settle(entry);
      expect(sent('stop'), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(sent('stop'), hasLength(1));
      expect(sent('start'), hasLength(1));
    },
  );

  test('nothing is sent off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await attach();
    await settle(manager.started(song('a')));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(calls, isEmpty);
  });

  test('progress follows the songs, at most once per interval', () async {
    await attach();
    final entries = [for (var i = 0; i < 10; i++) manager.started(song('s$i'))];
    await Future<void>.delayed(Duration.zero);
    for (final entry in entries) {
      manager.finished(entry);
    }
    await Future<void>.delayed(Duration.zero);
    // Ten songs settled at once: nothing yet, the interval has not passed.
    expect(sent('progress'), isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    final update = argumentsOf(sent('progress').single);
    expect(update['text'], '10 of 10 downloaded');
    expect(update['max'], 10);
    expect(update['current'], 10);
  });

  test('failed songs fill the bar but are not counted as downloaded', () async {
    await attach();
    final entries = [for (var i = 0; i < 4; i++) manager.started(song('f$i'))];
    await Future<void>.delayed(Duration.zero);
    manager
      ..finished(entries[0])
      ..failed(entries[1], StateError('x'))
      ..failed(entries[2], StateError('x'));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final update = argumentsOf(sent('progress').last);
    expect(update['text'], '1 of 4 downloaded');
    expect(update['current'], 3);
    final failure = argumentsOf(sent('failures').last);
    expect(failure['title'], 'Some downloads failed');
    expect(failure['text'], '2 songs failed');
  });

  test('the failure notice goes away when the failed song works', () async {
    await attach();
    await settle(manager.started(song('x')), fail: true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(sent('failures'), hasLength(1));
    expect(argumentsOf(sent('failures').single)['text'], '1 song failed');

    // Every batch start clears the last batch's notice, so count from here.
    final clearsBefore = sent('clearFailures').length;
    await settle(manager.started(song('x')));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(sent('clearFailures'), hasLength(clearsBefore + 1));
  });

  test('a batch that ends with failures leaves its summary', () async {
    await attach();
    await settle(manager.started(song('a')));
    await settle(manager.started(song('b')), fail: true);
    manager.failed(manager.started(song('c')), null);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(sent('stop'), hasLength(1));
    final last = argumentsOf(sent('failures').last);
    expect(last['text'], '2 songs failed, 1 unavailable');
    // The summary comes after the service has stopped.
    expect(
      calls.lastIndexWhere((call) => call.method == 'failures'),
      greaterThan(calls.indexWhere((call) => call.method == 'stop')),
    );
  });

  test('the next batch starts a service of its own', () async {
    await attach();
    await settle(manager.started(song('a')));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await settle(manager.started(song('b')));
    expect(sent('start'), hasLength(2));
    expect(argumentsOf(sent('start').last)['text'], '0 of 1 downloaded');
    expect(sent('clearFailures'), hasLength(2));
  });

  test('the permission is asked for once, only when not granted', () async {
    permissionGranted = false;
    await attach();
    await settle(manager.started(song('a')));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await settle(manager.started(song('b')));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sent('requestNotificationPermission'), hasLength(1));
  });

  test('a granted permission is not asked for', () async {
    await attach();
    await settle(manager.started(song('a')));
    expect(sent('requestNotificationPermission'), isEmpty);
  });

  test('downloads go on when Android refuses the service', () async {
    startRefused = true;
    await attach();
    final entry = manager.started(song('a'));
    await Future<void>.delayed(Duration.zero);
    await settle(entry);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(entry.status, DownloadStatus.done);
    expect(sent('progress'), isEmpty);
  });

  testWidgets('a tap while the app runs opens the downloads', (tester) async {
    notifications.attach(openDownloads: () => opened++);
    await tester.pump();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('openDownloads')),
      (_) {},
    );
    expect(opened, 0, reason: 'waits for the frame');
    await tester.pump();
    await tester.pump();
    expect(opened, 1);
    // The invariants are checked before the tear-down.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a tap that started the app opens the downloads', (tester) async {
    openedByTap = true;
    notifications.attach(openDownloads: () => opened++);
    await tester.pump();
    await tester.pump();
    expect(opened, 1);
    // The invariants are checked before the tear-down.
    debugDefaultTargetPlatformOverride = null;
  });
}
