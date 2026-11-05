import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/custom_search_bar.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/song_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  testWidgets(
    'filter stays live; Enter opens global and Back preserves it; offline stays local',
    (tester) async {
      var filter = '';
      final router = GoRouter(
        initialLocation: '/library',
        routes: [
          StatefulShellRoute.indexedStack(
            pageBuilder: (context, state, shell) =>
                NavigationManager.getPage(child: shell, state: state),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/library',
                    pageBuilder: (context, state) => NavigationManager.getPage(
                      state: state,
                      child: IslandScaffold(
                        title: 'Library',
                        onFilter: (query) => filter = query,
                        body: const Text('Original page'),
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/search',
                    pageBuilder: (context, state) => NavigationManager.getPage(
                      state: state,
                      child: const IslandScaffold(
                        title: 'Global search',
                        globalSearch: false,
                        body: Text('Global results'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      NavigationManager.router = router;
      for (final (offline, enabled) in [
        (false, true),
        (true, true),
        (false, false),
      ]) {
        offlineMode.value = offline;
        globalSearchOnEnter.value = enabled;
        router.go('/library');
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Blue hour');
        expect(filter, 'Blue hour');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        if (offline || !enabled) {
          expect(find.text('Global results'), findsNothing);
          expect(router.canPop(), isFalse);
        } else {
          expect(find.text('Global results'), findsOneWidget);
          expect(router.state.uri.queryParameters['q'], 'Blue hour');
          expect(router.canPop(), isTrue);
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          expect(find.text('Original page'), findsOneWidget);
          expect(find.widgetWithText(TextField, 'Blue hour'), findsOneWidget);
        }
        expect(filter, 'Blue hour');
        await tester.pumpWidget(const SizedBox());
        offlineMode.value = false;
        globalSearchOnEnter.value = true;
      }
      await tester.runAsync(
        () => Hive.box('settings').put('globalSearchOnEnter', false),
      );
      reloadSettingsFromStorage();
      expect(globalSearchOnEnter.value, isFalse);
      await tester.runAsync(
        () => Hive.box('settings').delete('globalSearchOnEnter'),
      );
      reloadSettingsFromStorage();
      expect(globalSearchOnEnter.value, isTrue);
      router.dispose();
    },
  );
  testWidgets(
    'the destination searches its term even with another cached search page',
    (tester) async {
      offlineMode.value = true;
      userLikedSongsList.value = [
        {'ytid': 'blue', 'title': 'Blue hour', 'artist': 'Artist'},
        {'ytid': 'sea', 'title': 'The Sea', 'artist': 'Artist'},
      ];
      userOfflineSongs.value = userLikedSongsList.value;
      searchHistoryNotifier.value = ['Blue hour', 'The Sea'];
      Widget app(String query) => localizedApp(
        IndexedStack(
          index: 1,
          children: [
            const SearchPage(key: ValueKey('cached')),
            SearchPage(key: const ValueKey('destination'), initialQuery: query),
          ],
        ),
      );
      await tester.pumpWidget(app('Blue hour'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomSearchBar>(find.byType(CustomSearchBar))
            .controller
            .text,
        'Blue hour',
      );
      expect(
        find.descendant(
          of: find.byType(SongBar),
          matching: find.text('Blue hour'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(app('The Sea'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomSearchBar>(find.byType(CustomSearchBar))
            .controller
            .text,
        'The Sea',
      );
      expect(
        find.descendant(
          of: find.byType(SongBar),
          matching: find.text('The Sea'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      offlineMode.value = false;
    },
  );
}
