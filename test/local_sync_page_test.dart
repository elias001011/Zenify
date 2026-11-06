import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/screens/local_sync_page.dart';
import 'package:musify/services/local_sync_service.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  final l10n = lookupAppLocalizations(const Locale('en'));
  final service = LocalSyncService.instance;

  tearDown(() {
    service.state.value = const LocalSyncState();
    localSyncEnabled.value = false;
  });

  Future<void> mount(WidgetTester tester, LocalSyncState state) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const LocalSyncPage()));
    // The page resets the status on its first frame; turning sync on only
    // afterwards keeps it from starting a real discovery.
    await tester.pump();
    localSyncEnabled.value = true;
    service.state.value = state;
    await tester.pump();
  }

  final statuses = <String, (LocalSyncState, String)>{
    'scanning': (
      const LocalSyncState(status: LocalSyncStatus.scanning),
      l10n.syncScanning,
    ),
    'syncing': (
      const LocalSyncState(status: LocalSyncStatus.syncing),
      l10n.syncConnecting,
    ),
    'success': (
      const LocalSyncState(status: LocalSyncStatus.success),
      l10n.syncSyncedAll,
    ),
  };

  for (final entry in statuses.entries) {
    testWidgets('the ${entry.key} status is announced as a live region', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (state, text) = entry.value;
      await mount(tester, state);

      expect(
        tester.getSemantics(find.text(text)),
        isSemantics(isLiveRegion: true),
      );
      // Only the status is live, not the page around it.
      expect(
        tester.getSemantics(find.text(l10n.syncData)),
        isSemantics(isLiveRegion: false),
      );
      semantics.dispose();
    });
  }

  testWidgets('the categories say which ones are selected', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, const LocalSyncState());

    expect(
      tester.getSemantics(find.text(l10n.syncFavourites)),
      isSemantics(isSelected: true),
    );
    semantics.dispose();
  });
}
