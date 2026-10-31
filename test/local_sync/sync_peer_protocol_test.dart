import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The headless sync peer in tools/sync_peer speaks the app's protocol with
/// its own copy of a few constants; they must not drift apart.
void main() {
  String? constant(String source, String name) =>
      RegExp('(?:static )?const (?:int |String )?_?$name\\s*=\\s*([^;]+);')
          .firstMatch(source)
          ?.group(1);

  final app = File('lib/services/local_sync_service.dart').readAsStringSync();
  final peer = File('tools/sync_peer/bin/zenify_sync_peer.dart')
      .readAsStringSync();

  for (final name in const [
    'discoveryPort',
    'apiVersion',
    'smallMessageBytes',
    'deviceHeader',
    'discoveryRequest',
    'discoveryResponse',
  ]) {
    test('the peer and the app agree on $name', () {
      final theirs = constant(app, name);
      expect(theirs, isNotNull, reason: '$name not found in the app');
      expect(constant(peer, name), theirs);
    });
  }
}
