import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/local_sync_page.dart';
import 'package:musify/services/local_sync_service.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('cancelling the PIN closes only the PIN dialog', (tester) async {
    final service = LocalSyncService.instance;
    final completer = Completer<bool>();
    service.incomingPairingRequest.value = IncomingPairingRequest(
      clientName: 'Phone',
      pin: '123456',
      completed: completer.future,
    );
    // Like the service: rejecting clears the request and completes it, before
    // the dialog is popped.
    void rejected() {
      if (service.incomingPairingRequest.value == null) {
        completer.complete(false);
      }
    }

    service.incomingPairingRequest.addListener(rejected);
    addTearDown(() {
      service.incomingPairingRequest.removeListener(rejected);
      service.incomingPairingRequest.value = null;
    });

    late BuildContext pageContext;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (home) => TextButton(
            onPressed: () => Navigator.of(home).push(
              MaterialPageRoute<void>(
                builder: (page) {
                  pageContext = page;
                  return const Scaffold(body: Text('sync page'));
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    showIncomingPairingDialog(inContext: pageContext);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('sync page'), findsOneWidget);
  });
}
