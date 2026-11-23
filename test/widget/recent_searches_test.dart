import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../support/recent_search_test_box.dart';

void main() {
  const user = 'search@example.com';
  const doctype = 'Sales Order';
  const resultRoute = '/search-result';
  const removeLabel = 'Remove from recent searches';
  const header = 'Recent searches';
  late RecentSearchTestBox box;
  late StorageService storage;
  late List<String> queries;

  setUp(() {
    box = RecentSearchTestBox();
    storage = StorageService.withStorage(box);
    queries = [];
  });

  DocTypeSearchDelegate apiDelegate() => DocTypeSearchDelegate(
    doctype: doctype,
    targetRoute: resultRoute,
    recentSearchStore: (storage: storage, user: user),
    searcher: (_, query) async {
      queries.add(query);
      return [
        GlobalSearchItem(
          id: 'SO-1',
          title: 'Sales order result',
          rawData: const {},
        ),
      ];
    },
  );

  Future<void> open(
    WidgetTester tester,
    SearchDelegate<void> delegate, {
    ThemeData? theme,
    String? prefill,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme,
        getPages: [
          GetPage(
            name: resultRoute,
            page: () => const Scaffold(body: Text('Result document')),
          ),
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSearch(
                context: context,
                delegate: delegate,
                query: prefill,
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
  }

  Future<void> seed(String context) async {
    await storage.addRecentSearch(context, user, 'Blue widgets');
    await storage.addRecentSearch(context, user, 'Office supplies');
  }

  testWidgets('API shows newest first and selecting a recent runs one search', (
    tester,
  ) async {
    await seed(doctype);
    await open(tester, apiDelegate());
    expect(find.text(header), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Office supplies')).dy,
      lessThan(tester.getTopLeft(find.text('Blue widgets')).dy),
    );
    expect(queries, isEmpty);

    await tester.tap(find.text('Blue widgets'));
    await tester.pumpAndSettle();
    expect(queries, ['Blue widgets']);
    expect(find.text('Sales order result'), findsOneWidget);
    expect(storage.getRecentSearches(doctype, user), [
      'Blue widgets',
      'Office supplies',
    ]);
  });

  testWidgets('API removes immediately and confirms clearing in place', (
    tester,
  ) async {
    await seed(doctype);
    await open(tester, apiDelegate());
    final remove = find.byTooltip(removeLabel);
    expect(tester.getSize(remove.first).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(remove.first);
    await tester.pumpAndSettle();
    expect(find.text('Office supplies'), findsNothing);
    expect(find.text('Blue widgets'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear recent searches?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Blue widgets'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text(header), findsNothing);
    expect(find.text('Type at least 3 characters'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(storage.getRecentSearches(doctype, user), isEmpty);
  });

  testWidgets('API typing filters history and only a result tap records', (
    tester,
  ) async {
    await seed(doctype);
    await open(tester, apiDelegate());
    final field = find.byType(TextField);
    await tester.enterText(field, 'LU');
    await tester.pumpAndSettle();
    expect(find.text('Blue widgets'), findsOneWidget);
    expect(find.text('Office supplies'), findsNothing);
    expect(find.text('Type at least 3 characters'), findsNothing);
    expect(queries, isEmpty);

    await tester.enterText(field, 'zz');
    await tester.pumpAndSettle();
    expect(find.text(header), findsNothing);
    expect(find.text('Type at least 3 characters'), findsOneWidget);

    await tester.enterText(field, '  Steel   bolts ');
    await tester.pumpAndSettle();
    expect(box.writes, 2);
    await tester.tap(find.text('Sales order result'));
    await tester.pumpAndSettle();
    expect(storage.getRecentSearches(doctype, user).first, 'Steel bolts');
    expect(find.text('Result document'), findsOneWidget);
  });

  testWidgets('opening a prefill does not save it until keyboard submit', (
    tester,
  ) async {
    await open(tester, apiDelegate(), prefill: '  SO-100  ');
    expect(storage.getRecentSearches(doctype, user), isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(storage.getRecentSearches(doctype, user), ['SO-100']);
    expect(queries, ['  SO-100  ']);
  });

  testWidgets(
    'local matches are above Apply and selecting applies and closes',
    (tester) async {
      const key = '/local-list';
      final changes = <String>[];
      await seed(key);
      await open(
        tester,
        DocTypeSearchDelegate(
          recentSearchKey: key,
          recentSearchStore: (storage: storage, user: user),
          onSearchChanged: changes.add,
        ),
      );
      await tester.enterText(find.byType(TextField), 'blue');
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Blue widgets')).dy,
        lessThan(tester.getTopLeft(find.text('Apply')).dy),
      );
      await tester.tap(find.text('Blue widgets'));
      await tester.pumpAndSettle();
      expect(changes.last, 'Blue widgets');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Open search'), findsOneWidget);
      expect(storage.getRecentSearches(key, user).first, 'Blue widgets');
    },
  );

  testWidgets('global shows its history below the scope chips', (tester) async {
    await seed('global');
    await open(
      tester,
      GlobalDocumentSearchDelegate(
        recentSearchStore: (storage: storage, user: user),
      ),
    );
    expect(find.text('Office supplies'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('All')).dy,
      lessThan(tester.getTopLeft(find.text(header)).dy),
    );
  });

  for (final keyboard in [false, true]) {
    final action = keyboard ? 'keyboard submit' : 'Apply';
    testWidgets('local $action saves and closes', (tester) async {
      const key = '/local-list';
      final changes = <String>[];
      await open(
        tester,
        DocTypeSearchDelegate(
          recentSearchKey: key,
          recentSearchStore: (storage: storage, user: user),
          onSearchChanged: changes.add,
        ),
      );
      await tester.enterText(find.byType(TextField), '  Steel   bolts ');
      await tester.pumpAndSettle();
      expect(storage.getRecentSearches(key, user), isEmpty);

      if (keyboard) {
        await tester.testTextInput.receiveAction(TextInputAction.search);
      } else {
        await tester.tap(find.text('Apply'));
      }
      await tester.pumpAndSettle();
      expect(changes.last, '  Steel   bolts ');
      expect(find.byType(TextField), findsNothing);
      expect(storage.getRecentSearches(key, user), ['Steel bolts']);
    });
  }

  testWidgets('recent-search rows use dark theme ink roles', (tester) async {
    await storage.addRecentSearch(doctype, user, 'Office supplies');
    await open(
      tester,
      apiDelegate(),
      theme: buildAppTheme(AppScheme.dark, Brightness.dark),
    );
    expect(
      tester.widget<Text>(find.text(header)).style?.color,
      AppScheme.dark.textMuted,
    );
    expect(
      tester.widget<Text>(find.text('Office supplies')).style?.color,
      AppScheme.dark.text,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.history)).color,
      AppScheme.dark.textSubtle,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close)).color,
      AppScheme.dark.textSubtle,
    );
  });
}
