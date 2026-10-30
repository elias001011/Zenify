import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/constants/version.dart';

void main() {
  late Directory directory;
  final script = File('scripts/release_version.sh').absolute;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zenify_release_version');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<ProcessResult> resolve(String manifest) async {
    final file = File('${directory.path}/pubspec.yaml');
    await file.writeAsString(manifest);
    return Process.run('bash', [script.path, file.path]);
  }

  test('normal releases exclude the platform build counter', () async {
    final result = await resolve('version: 0.1.7+8 # a normal release\n');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}'.trim(), '0.1.7');
  });

  test(
    'four-part hotfix stays separate from the Flutter semantic version',
    () async {
      final result = await resolve(
        'version: 0.1.7+9\nrelease_version: 0.1.7.1 # hotfix\n',
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}'.trim(), '0.1.7.1');
    },
  );

  test('a stale hotfix cannot override the next release', () async {
    final result = await resolve(
      'version: 0.1.8+10\nrelease_version: 0.1.7.1\n',
    );
    expect(result.exitCode, isNot(0));
  });

  test('missing SDK version cannot produce an empty release tag', () async {
    final result = await resolve('release_version: 0.1.7.1\n');
    expect(result.exitCode, isNot(0));
  });

  test('About and updater use the canonical release version', () async {
    final result = await Process.run('bash', [script.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}'.trim(), appVersion);
  });
}
