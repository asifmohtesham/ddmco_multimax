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

class _MemoryFormatStore implements SheetFormatStore {
  _MemoryFormatStore(this.saved);
  SheetFormat saved;

  @override
  SheetFormat read() => saved;

  @override
  void write(SheetFormat f) => saved = f;
}

/// Records the calls the screen makes instead of running a job.
class _SpyController extends StockSheetController {
  _SpyController({SheetFormat remembered = SheetFormat.excel})
    : super(formatStore: _MemoryFormatStore(remembered));

  final starts = <List<String>>[];
  final makes = <SheetFormat>[];
  final choices = <OutOfStockChoice?>[];
  int retries = 0;
  bool retryable = false;
  int onSheet = 0;

  @override
  bool get canRetry => retryable;

  @override
  int get sheetPhotoCount => onSheet;

  @override
  Future<void> start(List<String> paths) async {
    starts.add(paths);
  }

  @override
  Future<void> makeSheet(SheetFormat f) async {
    makes.add(f);
  }

  @override
  Future<void> chooseOutOfStock(OutOfStockChoice? choice) async {
    choices.add(choice);
    if (choice == null) phase.value = StockSheetPhase.reviewing;
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
    SheetFormat remembered = SheetFormat.excel,
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
        Get.put<StockSheetController>(
              _SpyController(remembered: remembered)..retryable = retryable,
            )
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

  testWidgets('a share starts reading at once, with no format question', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg', 'b.jpg']);

    expect(find.text('Make a stock sheet'), findsNothing);
    expect(controller.starts, [
      ['a.jpg', 'b.jpg'],
    ]);
    expect(find.byType(StockSheetScreen), findsOneWidget);
  });

  testWidgets('format sheet uses the dark themed surface', (tester) async {
    await open(tester);
    final picked = showFormatSheet(Get.context!, photoCount: 2);
    await tester.pumpAndSettle();

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
    expect(await picked, SheetFormat.pdf);
  });

  testWidgets('more than 100 photos goes to start, which refuses them', (
    tester,
  ) async {
    await open(tester, paths: List.generate(101, (i) => 'p$i.jpg'));
    expect(controller.starts.single, hasLength(101));
  });

  testWidgets('review: counts, and Make sheet in the remembered format', (
    tester,
  ) async {
    await open(tester, remembered: SheetFormat.both);
    expect(controller.format.value, SheetFormat.both);
    controller.onSheet = 1;
    controller.phase.value = StockSheetPhase.reviewing;
    await tester.pumpAndSettle();

    expect(find.text('Review photos'), findsOneWidget);
    expect(find.text('0 photos · 1 on the sheet'), findsOneWidget);
    await tester.tap(find.text('Make sheet · 1 photo'));
    await tester.pump();
    expect(controller.makes, [SheetFormat.both]);

    controller.errorMessage.value = "Couldn't build the sheet. Try again.";
    await tester.pumpAndSettle();
    final message = find.text("Couldn't build the sheet. Try again.");
    expect(message, findsOneWidget);
    expect(tester.widget<Text>(message).style?.color, AppColors.red300);
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

  testWidgets('dismissing the out-of-stock sheet goes back to the review', (
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
    expect(find.byType(StockSheetScreen), findsOneWidget);
    expect(find.text('Review photos'), findsOneWidget);
  });

  testWidgets('a new share during the out-of-stock question is held', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg']);
    controller.result.value = _result();
    controller.phase.value = StockSheetPhase.awaitingChoice;
    await tester.pumpAndSettle();
    expect(find.text('1 item is out of stock'), findsOneWidget);

    expect(
      controller.offerShare(['b.jpg', 'c.jpg', 'd.jpg']),
      ShareOffer.pending,
    );
    await tester.pumpAndSettle();

    // Nothing starts until the user answers (the screen's dialog asks).
    expect(controller.pendingShare, ['b.jpg', 'c.jpg', 'd.jpg']);
    expect(find.text('1 item is out of stock'), findsOneWidget);
    expect(controller.starts, [
      ['a.jpg'],
    ]);
    expect(controller.choices, isEmpty);
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
      XFile('/tmp/Items-20261117-0905.xlsx'),
      XFile('/tmp/Items-20261117-0905.pdf'),
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

  testWidgets('a share failure shows its message above Share files', (
    tester,
  ) async {
    await open(tester);
    controller.result.value = _result();
    controller.files.assignAll([XFile('/tmp/a.xlsx')]);
    controller.errorMessage.value = "Couldn't open the share sheet. Try again.";
    controller.phase.value = StockSheetPhase.done;
    await tester.pumpAndSettle();

    final message = find.text("Couldn't open the share sheet. Try again.");
    expect(message, findsOneWidget);
    expect(find.text('Share file'), findsOneWidget);
    expect(tester.widget<Text>(message).style?.color, AppColors.red300);
    expect(
      tester.getTopLeft(message).dy,
      lessThan(tester.getTopLeft(find.text('Share file')).dy),
    );

    controller.errorMessage.value = null;
    await tester.pumpAndSettle();
    expect(message, findsNothing);
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
