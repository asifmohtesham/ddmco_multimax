import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_screen.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/format_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:share_plus/share_plus.dart';

/// Records the calls the screen makes instead of running a job.
class _SpyController extends StockSheetController {
  final starts = <(List<String>, SheetFormat)>[];
  final choices = <OutOfStockChoice?>[];
  int retries = 0;
  bool retryable = false;

  @override
  bool get canRetry => retryable;

  @override
  Future<void> start(List<String> paths, SheetFormat format) async {
    starts.add((paths, format));
  }

  @override
  Future<void> chooseOutOfStock(OutOfStockChoice? choice) async {
    choices.add(choice);
    if (choice == null) phase.value = StockSheetPhase.idle;
  }

  @override
  Future<void> retry() async => retries++;
}

StockSheetResult _result({int rows = 2, int outOfStock = 1}) =>
    StockSheetResult(
      rows: [
        for (var i = 0; i < rows; i++)
          StockSheetRow(
            photoIndex: i,
            photoPath: 'p$i.jpg',
            barcode: '1000001$i',
            itemName: 'Item $i',
            outOfStock: i < outOfStock,
          ),
      ],
      unresolved: const [
        UnresolvedEntry(
          photoIndex: 5,
          photoPath: 'p5.jpg',
          reason: UnresolvedReason.unreadable,
        ),
        UnresolvedEntry(
          photoIndex: 6,
          photoPath: 'p6.jpg',
          reason: UnresolvedReason.noRecognisedCode,
        ),
        UnresolvedEntry(
          photoIndex: 7,
          photoPath: 'p7.jpg',
          reason: UnresolvedReason.notInErp,
          barcode: '99999995',
        ),
      ],
    );

void main() {
  final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
  late _SpyController controller;

  tearDown(Get.reset);

  /// Opens the screen on top of a blank home, so closing it is observable.
  /// The controller is registered once the home route exists, so GetX ties
  /// it to that route and not to a previous test's.
  Future<void> open(
    WidgetTester tester, {
    List<String>? paths,
    bool retryable = false,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Text('home')),
      ),
    );
    controller =
        Get.put<StockSheetController>(_SpyController()..retryable = retryable)
            as _SpyController;
    Get.to<void>(() => StockSheetScreen(paths: paths ?? const []));
    await tester.pumpAndSettle();
  }

  /// The colour of the nearest Material above [inner] that paints one.
  Color? surfaceAbove(WidgetTester tester, Finder inner) {
    for (final e
        in find
            .ancestor(of: inner, matching: find.byType(Material))
            .evaluate()) {
      final colour = (e.widget as Material).color;
      if (colour != null && colour.a > 0) return colour;
    }
    return null;
  }

  testWidgets('format sheet uses the dark themed surface and starts the run', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg', 'b.jpg']);

    expect(find.text('Make a stock sheet'), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.text('Excel and PDF'), findsOneWidget);

    final surface = surfaceAbove(tester, find.text('Make a stock sheet'));
    expect(surface, AppScheme.dark.fg);
    expect(surface, darkTheme.colorScheme.surface);
    final sheetColours = [
      for (final e
          in find
              .descendant(
                of: find.byType(FormatSheet),
                matching: find.byType(Material),
              )
              .evaluate())
        (e.widget as Material).color,
      for (final e
          in find
              .descendant(
                of: find.byType(FormatSheet),
                matching: find.byType(Container),
              )
              .evaluate())
        if ((e.widget as Container).decoration case BoxDecoration(:final color))
          color,
    ];
    expect(sheetColours, isNot(contains(Colors.white)));

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(controller.starts.single.$1, ['a.jpg', 'b.jpg']);
    expect(controller.starts.single.$2, SheetFormat.pdf);
  });

  testWidgets('dismissing the format sheet closes the screen', (tester) async {
    await open(tester, paths: ['a.jpg']);
    expect(find.text('1 photo'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20)); // the barrier
    await tester.pumpAndSettle();

    expect(find.byType(StockSheetScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(controller.starts, isEmpty);
  });

  testWidgets('more than 100 photos skips the format question', (tester) async {
    await open(tester, paths: List.generate(101, (i) => 'p$i.jpg'));
    expect(find.text('Make a stock sheet'), findsNothing);
    expect(controller.starts.single.$1, hasLength(101));
  });

  testWidgets('out-of-stock sheet offers the three choices', (tester) async {
    await open(tester);
    controller.result.value = _result(rows: 3, outOfStock: 2);
    controller.phase.value = StockSheetPhase.awaitingChoice;
    await tester.pumpAndSettle();

    expect(find.text('2 items are out of stock'), findsOneWidget);
    expect(find.text('Include, colour red'), findsOneWidget);
    expect(find.text('Include, no colour'), findsOneWidget);
    await tester.tap(find.text('Leave them out'));
    await tester.pumpAndSettle();

    expect(controller.choices, [OutOfStockChoice.leaveOut]);
    expect(find.byType(StockSheetScreen), findsOneWidget);
  });

  testWidgets('dismissing the out-of-stock sheet cancels and closes', (
    tester,
  ) async {
    await open(tester);
    controller.result.value = _result();
    controller.phase.value = StockSheetPhase.awaitingChoice;
    await tester.pumpAndSettle();
    expect(find.text('1 item is out of stock'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(controller.choices, [null]);
    expect(find.byType(StockSheetScreen), findsNothing);
  });

  testWidgets('a new share while the format sheet is open replaces it', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg']);
    expect(find.text('1 photo'), findsOneWidget);

    controller.takeShare(['b.jpg', 'c.jpg', 'd.jpg']);
    await tester.pumpAndSettle();

    expect(find.text('Make a stock sheet'), findsOneWidget);
    expect(find.text('3 photos'), findsOneWidget);
    expect(find.byType(StockSheetScreen), findsOneWidget);

    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    expect(controller.starts.single.$1, ['b.jpg', 'c.jpg', 'd.jpg']);
    expect(controller.starts.single.$2, SheetFormat.excel);
  });

  testWidgets('progress shows the photo count, then the ERP steps', (
    tester,
  ) async {
    await open(tester);
    controller.total.value = 23;
    controller.decoded.value = 6;
    controller.phase.value = StockSheetPhase.decoding;
    await tester.pump();

    expect(find.text('Reading photo 7 of 23'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(6 / 23, 1e-9));

    controller.phase.value = StockSheetPhase.checkingStock;
    await tester.pump();
    expect(find.text('Checking stock…'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    controller.phase.value = StockSheetPhase.building;
    await tester.pump();
    expect(find.text('Building file…'), findsOneWidget);
  });

  testWidgets('result: share button swaps for a spinner while sharing', (
    tester,
  ) async {
    await open(tester);
    controller.total.value = 8;
    controller.result.value = _result();
    controller.files.assignAll([
      XFile('/tmp/stock-sheet-20261117-0905.xlsx'),
      XFile('/tmp/stock-sheet-20261117-0905.pdf'),
    ]);
    controller.phase.value = StockSheetPhase.done;
    await tester.pumpAndSettle();

    expect(find.text('Share files'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    final shareButton = find.ancestor(
      of: find.text('Share files'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(
      find.descendant(
        of: shareButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    controller.sharing.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: shareButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ButtonStyleButton>(shareButton).onPressed, isNull);

    controller.sharing.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('one file says "Share file"; no rows says nothing to share', (
    tester,
  ) async {
    await open(tester);
    controller.result.value = _result();
    controller.files.assignAll([XFile('/tmp/a.xlsx')]);
    controller.phase.value = StockSheetPhase.done;
    await tester.pumpAndSettle();
    expect(find.text('Share file'), findsOneWidget);

    controller.files.clear();
    controller.result.value = _result(rows: 0, outOfStock: 0);
    await tester.pumpAndSettle();
    expect(find.text('Share file'), findsNothing);
    expect(find.text('Nothing to put on a sheet.'), findsOneWidget);
  });

  testWidgets('result list: sections, reasons, and it ends with End of list', (
    tester,
  ) async {
    await open(tester);
    controller.total.value = 8;
    controller.result.value = _result(rows: 2, outOfStock: 1);
    controller.files.assignAll([XFile('/tmp/a.xlsx')]);
    controller.phase.value = StockSheetPhase.done;
    await tester.pumpAndSettle();

    expect(find.text('8 photos · 2 items · 1 out of stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    final oosName = tester.widget<Text>(find.text('Item 0'));
    expect(oosName.style?.color, AppColors.red300);

    expect(find.byType(Scrollbar), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('End of list'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text("Couldn't use these photos"), findsOneWidget);
    expect(find.text('Unreadable photo'), findsOneWidget);
    expect(find.text('No recognised code'), findsOneWidget);
    expect(find.text('Not in ERP: 99999995'), findsOneWidget);

    final endY = tester.getTopLeft(find.text('End of list')).dy;
    final lastEntryY = tester.getTopLeft(find.text('Not in ERP: 99999995')).dy;
    expect(endY, greaterThan(lastEntryY));
  });

  testWidgets('error view offers Retry only after decoding', (tester) async {
    await open(tester);
    controller.errorMessage.value = "Couldn't reach the ERP.";
    controller.phase.value = StockSheetPhase.error;
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reach the ERP."), findsOneWidget);
    // Nothing decoded in this spy, so there is nothing to retry.
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(StockSheetScreen), findsNothing);
  });

  testWidgets('Retry reruns the ERP step and spins while busy', (tester) async {
    await open(tester, retryable: true);
    controller.errorMessage.value = "You don't have access to stock levels.";
    controller.phase.value = StockSheetPhase.error;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(controller.retries, 1);

    controller.busy.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    final retryButton = find.ancestor(
      of: find.text('Retry'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(
      find.descendant(
        of: retryButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    controller.busy.value = false;
    await tester.pumpAndSettle();
  });
}
