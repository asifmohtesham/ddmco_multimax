import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/awesome_bar_option.dart';
import 'package:multimax/app/data/services/awesome_bar_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/awesome_bar_delegate.dart';
import 'package:multimax/app/modules/global_widgets/search_highlight.dart';
import 'package:multimax/main.dart' show buildAppTheme;

class FakeBox {
  final Map<String, dynamic> data = {};
  T? read<T>(String key) => data[key] as T?;
  Future<void> write(String key, dynamic value) async => data[key] = value;
  Future<void> remove(String key) async => data.remove(key);
  bool hasData(String key) => data.containsKey(key);
}

final AwesomeBarRegistry kRegistry = AwesomeBarRegistry(
  doctypes: const [
    AwesomeBarDoctype(
        doctype: 'Delivery Note', label: 'Delivery Note', listRoute: '/dn'),
  ],
  reports: const [],
  pages: const [],
  targets: [
    GlobalSearchTarget(
      doctype: 'Delivery Note',
      label: 'Delivery Notes',
      icon: Icons.local_shipping_outlined,
      color: Colors.blue,
      route: '/dn/form',
      argsFor: (id) => {'name': id, 'mode': 'view'},
      newArgs: const {'name': '', 'mode': 'new'},
    ),
  ],
);

AwesomeBarService _service() => AwesomeBarService(
      registry: kRegistry,
      recents: AwesomeBarRecentsStore(
        storage: StorageService.withStorage(FakeBox()),
        user: () => 'a@x.com',
      ),
    );

Finder _row(AwesomeBarOptionType type, String value) =>
    find.byKey(ValueKey('awesome-bar:${type.name}:$value'));

void main() {
  setUp(() => Get.reset());

  group('buildOptionList', () {
    final options = [
      AwesomeBarService.makeGlobalSearch('dn'),
      const AwesomeBarOption(
        type: AwesomeBarOptionType.list,
        match: 'Delivery Note',
        matchIndices: [0, 9],
        labelSuffix: ' List',
        value: 'Delivery Note List',
        index: 134.05,
        route: '/dn',
        dedupeKey: 'list:Delivery Note',
      ),
      const AwesomeBarOption(
        type: AwesomeBarOptionType.document,
        match: 'KA-DN-1',
        value: 'KA-DN-1',
        index: 0,
        route: '/dn/form',
        doctype: 'Delivery Note',
        docname: 'KA-DN-1',
        description: 'Customer: Acme',
      ),
      AwesomeBarService.helpOption(),
    ];

    testWidgets('renders sections in order and fires onTap', (tester) async {
      final delegate = AwesomeBarDelegate(service: _service());
      AwesomeBarOption? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => delegate.buildOptionList(
              context,
              options,
              onTap: (o) => tapped = o,
            ),
          ),
        ),
      ));

      expect(find.text('LISTS'), findsOneWidget);
      expect(find.text('DOCUMENTS'), findsOneWidget);
      expect(find.text('End of list'), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(find.text('Delivery Note · Customer: Acme'), findsOneWidget);

      // Search row first, help last.
      final searchY = tester.getTopLeft(_row(AwesomeBarOptionType.search, 'Search for dn')).dy;
      final listY = tester.getTopLeft(_row(AwesomeBarOptionType.list, 'Delivery Note List')).dy;
      final helpY = tester.getTopLeft(_row(AwesomeBarOptionType.help, 'Help on Search')).dy;
      expect(searchY, lessThan(listY));
      expect(listY, lessThan(helpY));

      await tester.tap(_row(AwesomeBarOptionType.list, 'Delivery Note List'));
      expect(tapped?.route, '/dn');
    });

    testWidgets('emphasises the fuzzy-matched characters', (tester) async {
      final delegate = AwesomeBarDelegate(service: _service());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                delegate.buildOptionList(context, options, onTap: (_) {}),
          ),
        ),
      ));
      final hl = tester.widget<MatchIndexHighlight>(find.descendant(
        of: _row(AwesomeBarOptionType.list, 'Delivery Note List'),
        matching: find.byType(MatchIndexHighlight),
      ));
      expect(hl.indices, [0, 9]);
      final rich = tester.widget<RichText>(find.descendant(
        of: find.byWidget(hl),
        matching: find.byType(RichText),
      ));
      final spans = (rich.text as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((s) => s.text), ['D', 'elivery ', 'N', 'ote', ' List']);
      expect(spans[0].style?.fontWeight, FontWeight.w700);
      expect(spans[1].style, isNull);
    });

    testWidgets('uses themed surfaces and inks in dark mode', (tester) async {
      final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
      final delegate = AwesomeBarDelegate(service: _service());
      await tester.pumpWidget(MaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                delegate.buildOptionList(context, options, onTap: (_) {}),
          ),
        ),
      ));
      final container = tester.widget<Container>(find
          .ancestor(of: find.byType(Scrollbar), matching: find.byType(Container))
          .first);
      expect(container.color, AppScheme.dark.bg);
      final header = tester.widget<Text>(find.text('LISTS'));
      expect(header.style?.color, AppScheme.dark.textMuted);
      final sub = tester.widget<Text>(find.text('Delivery Note · Customer: Acme'));
      expect(sub.style?.color, AppScheme.dark.textMuted);
    });

    testWidgets('an empty option list shows the prompt and the footer',
        (tester) async {
      final delegate = AwesomeBarDelegate(service: _service());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                delegate.buildOptionList(context, const [], onTap: (_) {}),
          ),
        ),
      ));
      expect(find.textContaining('Type to search'), findsOneWidget);
      expect(find.text('End of list'), findsOneWidget);
    });
  });

  group('busy flag', () {
    testWidgets('progress indicator toggles with busy', (tester) async {
      final delegate = AwesomeBarDelegate(service: _service());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: delegate.buildProgress()),
      ));
      expect(find.byType(LinearProgressIndicator), findsNothing);

      delegate.busy.value = true;
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      delegate.busy.value = false;
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('showSearch integration', () {
    Widget app(AwesomeBarDelegate delegate, {String query = ''}) =>
        GetMaterialApp(
          getPages: [
            GetPage(
              name: '/',
              page: () => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showSearch<void>(
                      context: context,
                      delegate: delegate,
                      query: query,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            GetPage(
              name: '/dn',
              page: () => Scaffold(
                body: Builder(
                  builder: (context) =>
                      Text('DN LIST ${Get.arguments ?? 'no-args'}'),
                ),
              ),
            ),
          ],
        );

    testWidgets('"Search for x" closes the bar and opens the document search',
        (tester) async {
      String? opened;
      final searched = <String>[];
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (t) async {
          searched.add(t);
          return const [];
        },
        openDocumentSearch: (ctx, q) => opened = q,
      );
      await tester.pumpWidget(app(delegate, query: 'dn'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(_row(AwesomeBarOptionType.search, 'Search for dn'), findsOneWidget);
      // Nav options render synchronously; the global call is debounced.
      expect(_row(AwesomeBarOptionType.list, 'Delivery Note List'), findsOneWidget);
      expect(_row(AwesomeBarOptionType.newDoc, 'New Delivery Note'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(searched, ['dn']);

      await tester.tap(_row(AwesomeBarOptionType.search, 'Search for dn'));
      await tester.pumpAndSettle();
      expect(opened, 'dn');
      expect(find.byType(TextField), findsNothing);
      expect(delegate.query, '');
    });

    testWidgets('tapping a List option navigates to its route', (tester) async {
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (_) async => const [],
      );
      await tester.pumpWidget(app(delegate, query: 'deliv'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(_row(AwesomeBarOptionType.list, 'Delivery Note List'));
      await tester.pumpAndSettle();
      expect(find.text('DN LIST no-args'), findsOneWidget);
    });

    testWidgets('"Find x in DocType" passes the query argument', (tester) async {
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (_) async => const [],
      );
      await tester.pumpWidget(app(delegate, query: 'acme in deliv'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(_row(AwesomeBarOptionType.inList, 'Find acme in Delivery Note'));
      await tester.pumpAndSettle();
      expect(find.text('DN LIST {awesomeBarQuery: acme}'), findsOneWidget);
    });

    testWidgets('global results appear under Documents once fetched',
        (tester) async {
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (t) async => AwesomeBarService.documentOptions(
          const [
            GlobalSearchHit(
                doctype: 'Delivery Note',
                name: 'KA-DN-0012',
                content: 'Customer : Acme'),
          ],
          t,
          kRegistry,
        ),
      );
      await tester.pumpWidget(app(delegate, query: 'acme'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('DOCUMENTS'), findsOneWidget);
      expect(_row(AwesomeBarOptionType.document, 'KA-DN-0012'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Escape closes the bar', (tester) async {
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (_) async => const [],
      );
      await tester.pumpWidget(app(delegate));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the calculator row shows its result in a dialog',
        (tester) async {
      final delegate = AwesomeBarDelegate(
        service: _service(),
        globalSearcher: (_) async => const [],
      );
      await tester.pumpWidget(app(delegate, query: '=2^10'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_row(AwesomeBarOptionType.calculator, '2^10 = 1024'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('2^10 = 1024'), findsWidgets);
    });
  });
}
