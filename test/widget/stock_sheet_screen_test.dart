import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_screen.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/out_of_stock_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/review_list.dart';
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
    : super(
        formatStore: _MemoryFormatStore(remembered),
        fingerprint: (paths) async => {
          for (final path in paths) path: _fingerprints[path] ?? 'fp:$path',
        },
      );

  /// Fixed fingerprints by path; any other path is its own content.
  static final _fingerprints = <String, String>{};

  final starts = <List<String>>[];
  final makes = <SheetFormat>[];
  final choices = <OutOfStockChoice?>[];
  final added = <List<String>>[];
  String? addError;

  /// When set, answers [addPhotos] instead of [addError].
  Future<String?> Function(List<String> paths)? onAdd;

  final rechecks = <int>[];
  String? recheckError;
  int retries = 0;
  bool retryable = false;

  /// Overrides the count of photos on the sheet; null counts [review].
  int? onSheet;

  @override
  bool get canRetry => retryable;

  @override
  int get sheetPhotoCount => onSheet ?? super.sheetPhotoCount;

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
  Future<String?> addPhotos(List<String> paths) async {
    added.add(paths);
    return onAdd != null ? onAdd!(paths) : addError;
  }

  @override
  Future<String?> retryCheck(int index) async {
    rechecks.add(index);
    return recheckError;
  }

  @override
  Future<void> retry() async => retries++;
}

ReviewItem _item(String barcode) => ReviewItem(
  code: ClassifiedCode(itemCode: barcode.substring(0, 7), barcode: barcode),
  info: ItemInfo(itemCode: barcode.substring(0, 7), itemName: 'Item $barcode'),
  stock: const ItemStock(
    total: 12,
    racks: [RackQty(rack: 'KA-WH-DXB1-21A', qty: 12)],
  ),
);

/// Two photos with one known item each.
List<ReviewEntry> _twoPhotos() => [
  ReviewEntry(path: 'a.jpg', items: [_item('12345670')]),
  ReviewEntry(path: 'b.jpg', items: [_item('76543210')]),
];

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

  tearDown(() {
    _SpyController._fingerprints.clear();
    Get.reset();
  });

  /// Opens the screen on top of a blank home, so closing it is observable.
  /// The controller is registered once the home route exists, so GetX ties
  /// it to that route and not to a previous test's.
  Future<void> open(
    WidgetTester tester, {
    List<String>? paths,
    bool retryable = false,
    SheetFormat remembered = SheetFormat.excel,
    Future<List<String>> Function()? pickCamera,
    Future<List<String>> Function()? pickGallery,
    Future<List<String>> Function()? pickFiles,
    bool onMac = false,
    ThemeData? theme,
  }) async {
    final t = theme ?? darkTheme;
    await tester.pumpWidget(
      GetMaterialApp(
        theme: t,
        darkTheme: t,
        themeMode: t.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: const Scaffold(body: Text('home')),
      ),
    );
    controller =
        Get.put<StockSheetController>(
              _SpyController(remembered: remembered)..retryable = retryable,
            )
            as _SpyController;
    Get.to<void>(
      () => StockSheetScreen(
        paths: paths ?? const [],
        pickCamera: pickCamera ?? () async => const [],
        pickGallery: pickGallery ?? () async => const [],
        pickFiles: pickFiles ?? () async => const [],
        runningOnMac: () async => onMac,
      ),
    );
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

  /// Puts [entries] on screen in the review phase.
  Future<void> review(WidgetTester tester, List<ReviewEntry> entries) async {
    controller.review.assignAll(entries);
    controller.phase.value = StockSheetPhase.reviewing;
    await tester.pumpAndSettle();
  }

  testWidgets('a share opens into reading, then the review list', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg', 'b.jpg']);

    expect(find.text('Make a stock sheet'), findsNothing);
    expect(controller.starts, [
      ['a.jpg', 'b.jpg'],
    ]);

    controller.total.value = 2;
    controller.phase.value = StockSheetPhase.decoding;
    await tester.pump();
    expect(find.text('Reading photo 1 of 2'), findsOneWidget);
    expect(find.text('Items from Photos'), findsOneWidget);

    await review(tester, _twoPhotos());
    expect(find.text('Make a stock sheet'), findsNothing);
    expect(find.byType(ReviewList), findsOneWidget);
    expect(find.text('Item 12345670'), findsOneWidget);
    expect(find.text('Review photos'), findsOneWidget);
    expect(find.text('2 photos · 2 in the file'), findsOneWidget);
    expect(find.text('Generate file · 2 photos'), findsOneWidget);
  });

  testWidgets('the format control shows the stored format', (tester) async {
    await open(tester, remembered: SheetFormat.pdf);
    await review(tester, _twoPhotos());

    final control = tester.widget<SegmentedButton<SheetFormat>>(
      find.byType(SegmentedButton<SheetFormat>),
    );
    expect(control.selected, {SheetFormat.pdf});
    expect(find.text('Excel'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Both'), findsOneWidget);

    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();
    expect(controller.format.value, SheetFormat.both);
    await tester.tap(find.text('Generate file · 2 photos'));
    await tester.pump();
    expect(controller.makes, [SheetFormat.both]);
  });

  testWidgets('Generate file is disabled once both photos are switched off', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());

    ButtonStyleButton button(String label) => tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button('Generate file · 2 photos').onPressed, isNotNull);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    expect(find.text('Generate file · 1 photo'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(find.text('2 photos · 0 in the file'), findsOneWidget);
    expect(button('Generate file · 0 photos').onPressed, isNull);
    await tester.tap(find.text('Generate file · 0 photos'));
    await tester.pump();
    expect(controller.makes, isEmpty);
  });

  testWidgets('Back while reviewing asks first; Keep reviewing stays', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these photos?'), findsOneWidget);
    await tester.tap(find.text('Keep reviewing'));
    await tester.pumpAndSettle();

    expect(find.text('Discard these photos?'), findsNothing);
    expect(find.byType(StockSheetScreen), findsOneWidget);
    expect(find.byType(ReviewList), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(StockSheetScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Back outside the review leaves at once', (tester) async {
    await open(tester);
    controller.phase.value = StockSheetPhase.decoding;
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard these photos?'), findsNothing);
    expect(find.byType(StockSheetScreen), findsNothing);
  });

  testWidgets('a share during the review asks Add, Start again or Cancel', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg', 'b.jpg']);
    await review(tester, _twoPhotos());

    expect(
      controller.offerShare(['n1.jpg', 'n2.jpg', 'n3.jpg']),
      ShareOffer.pending,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Add these 3 photos to the list, or start again?'),
      findsOneWidget,
    );
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Start again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(controller.added, [
      ['n1.jpg', 'n2.jpg', 'n3.jpg'],
    ]);
    expect(controller.pendingShare, isEmpty);
    expect(find.byType(ReviewList), findsOneWidget);
  });

  testWidgets('a share that will not fit offers only Start again', (
    tester,
  ) async {
    await open(tester, paths: ['a.jpg']);
    await review(tester, [
      for (var i = 0; i < 99; i++)
        ReviewEntry(path: 'p$i.jpg', decodeFailed: true),
    ]);

    controller.offerShare(['n1.jpg', 'n2.jpg', 'n3.jpg']);
    await tester.pumpAndSettle();

    expect(find.text('Only 1 more photo fits (limit 100).'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Start again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Start again'));
    await tester.pumpAndSettle();
    expect(controller.starts.last, ['n1.jpg', 'n2.jpg', 'n3.jpg']);
    expect(controller.review, isEmpty);
  });

  testWidgets('an Add that no longer fits once an add lands asks again', (
    tester,
  ) async {
    await open(tester);
    await review(tester, [
      for (var i = 0; i < 97; i++)
        ReviewEntry(path: 'p$i.jpg', decodeFailed: true),
    ]);
    // Another add lands first and takes two of the three places left.
    controller.onAdd = (_) async {
      controller.review.addAll([
        ReviewEntry(path: 'x1.jpg', decodeFailed: true),
        ReviewEntry(path: 'x2.jpg', decodeFailed: true),
      ]);
      return StockSheetController.roomMessage(1);
    };

    controller.offerShare(['n1.jpg', 'n2.jpg']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(controller.pendingShare, ['n1.jpg', 'n2.jpg']);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Only 1 more photo fits (limit 100).'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Start again'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.pendingShare, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a second share joins the open question and its count', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());

    controller.offerShare(['n1.jpg']);
    await tester.pumpAndSettle();
    expect(
      find.text('Add this photo to the list, or start again?'),
      findsOneWidget,
    );

    controller.offerShare(['n2.jpg', 'n1.jpg', 'n3.jpg']);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Add these 3 photos to the list, or start again?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(controller.added, [
      ['n1.jpg', 'n2.jpg', 'n3.jpg'],
    ]);
  });

  testWidgets('a share while photos are being added is asked about', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());
    controller.adding.value = true;

    expect(controller.offerShare(['n1.jpg']), ShareOffer.pending);
    // The + spinner never settles, so pump a fixed time.
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Add this photo to the list, or start again?'),
      findsOneWidget,
    );

    controller.adding.value = false;
    await tester.pumpAndSettle();
  });

  testWidgets('Generate file is disabled while a typed code is looked up', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());
    ButtonStyleButton button() => tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Generate file · 2 photos'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button().onPressed, isNotNull);

    controller.fixing.value = true;
    await tester.pump();
    expect(button().onPressed, isNull);

    controller.fixing.value = false;
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('swipe shows "Photo removed." and Undo restores the row', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());
    final before = tester.getTopLeft(find.text('Item 12345670'));

    await tester.drag(find.text('Item 12345670'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Item 12345670'), findsNothing);
    expect(find.text('Photo removed.'), findsOneWidget);
    expect(controller.review.map((e) => e.path), ['b.jpg']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(controller.review.map((e) => e.path), ['a.jpg', 'b.jpg']);
    expect(tester.getTopLeft(find.text('Item 12345670')), before);
  });

  testWidgets('no swipe while the out-of-stock question is open', (
    tester,
  ) async {
    await open(tester);
    await review(tester, _twoPhotos());
    controller.phase.value = StockSheetPhase.awaitingChoice;
    await tester.pumpAndSettle();

    await tester.drag(find.text('Item 12345670'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(controller.canRemove, isFalse);
    expect(find.text('Item 12345670'), findsOneWidget);
    expect(controller.review, hasLength(2));
  });

  testWidgets('a failed Retry check says why in a snackbar', (tester) async {
    await open(tester);
    controller.recheckError = StockSheetController.offlineMessage;
    await review(tester, [
      ReviewEntry(path: 'a.jpg', items: [_item('12345670')]),
      ReviewEntry(
        path: 'd.jpg',
        rawValues: const ['12345670'],
        unchecked: true,
      ),
    ]);

    await tester.tap(find.text('Retry check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.rechecks, [1]);
    expect(find.text(StockSheetController.offlineMessage), findsOneWidget);
  });

  testWidgets(
    'a re-shared duplicate shows "Those photos are already in the list."',
    (tester) async {
      await open(tester);
      _SpyController._fingerprints.addAll({'a.jpg': 'X', 'copy.jpg': 'X'});
      await review(tester, _twoPhotos());

      controller.offerShare(['copy.jpg']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text(StockSheetController.alreadyListedMessage),
        findsOneWidget,
      );
      expect(controller.pendingShare, isEmpty);
    },
  );

  testWidgets('Cancel keeps the review and drops the share', (tester) async {
    await open(tester);
    await review(tester, _twoPhotos());

    controller.offerShare(['n1.jpg']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.pendingShare, isEmpty);
    expect(controller.added, isEmpty);
    expect(controller.review, hasLength(2));
    expect(find.byType(ReviewList), findsOneWidget);
  });

  testWidgets('Add during the out-of-stock question closes that sheet', (
    tester,
  ) async {
    await open(tester);
    controller.review.assignAll(_twoPhotos());
    controller.result.value = _result();
    controller.phase.value = StockSheetPhase.awaitingChoice;
    await tester.pumpAndSettle();
    expect(find.text('1 item is out of stock'), findsOneWidget);

    controller.offerShare(['n1.jpg']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('1 item is out of stock'), findsNothing);
    expect(controller.phase.value, StockSheetPhase.reviewing);
    expect(controller.added, [
      ['n1.jpg'],
    ]);
    // The closed sheet's late answer is not taken as a choice.
    expect(controller.choices, isEmpty);
  });

  testWidgets('opened without photos shows the start panel', (tester) async {
    await open(tester);

    expect(
      find.text(
        'Choose photos of item labels to list their stock as Excel or PDF.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose files…'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
  });

  testWidgets('on a Mac the camera is hidden and the drag hint shows', (
    tester,
  ) async {
    await open(tester, onMac: true);

    expect(find.text('Take a photo'), findsNothing);
    expect(
      find.text(
        'On a Mac you can also drag photos here or share them from Finder.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Choose files… starts a run with the picked files', (
    tester,
  ) async {
    await open(tester, pickFiles: () async => ['/f/a.jpg']);

    await tester.tap(find.text('Choose files…'));
    await tester.pumpAndSettle();
    expect(controller.starts, [
      ['/f/a.jpg'],
    ]);
  });

  testWidgets('opened with shared photos shows no start panel', (tester) async {
    await open(tester, paths: ['a.jpg']);

    expect(find.text('Choose files…'), findsNothing);
  });

  testWidgets('the + menu offers Choose files… and adds the picked files', (
    tester,
  ) async {
    await open(tester, pickFiles: () async => ['/f/b.jpg']);
    await review(tester, _twoPhotos());

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose files…'));
    await tester.pumpAndSettle();
    expect(controller.added, [
      ['/f/b.jpg'],
    ]);
  });

  testWidgets('the + menu hides Take a photo on a Mac', (tester) async {
    await open(tester, onMac: true);
    await review(tester, _twoPhotos());

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    expect(find.text('Choose files…'), findsOneWidget);
    expect(find.text('Take a photo'), findsNothing);
  });

  testWidgets('the + menu adds photos from the gallery', (tester) async {
    await open(
      tester,
      pickGallery: () async => ['g1.jpg', 'g2.jpg'],
      pickCamera: () async => ['c1.jpg'],
    );
    await review(tester, _twoPhotos());

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(controller.added, [
      ['g1.jpg', 'g2.jpg'],
    ]);

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(controller.added.last, ['c1.jpg']);
  });

  testWidgets('an add that is refused says why in a snackbar', (tester) async {
    await open(tester, pickGallery: () async => ['g1.jpg']);
    controller.addError = 'Only 0 more photos fit (limit 100).';
    await review(tester, _twoPhotos());

    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Only 0 more photos fit (limit 100).'), findsOneWidget);
  });

  testWidgets('the + spinner is visible on the light-mode app bar', (
    tester,
  ) async {
    final lightTheme = buildAppTheme(AppScheme.light, Brightness.light);
    await open(tester, theme: lightTheme);
    await review(tester, _twoPhotos());

    controller.adding.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    final spinner = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(spinner.color, lightTheme.colorScheme.onPrimary);
    controller.adding.value = false;
    await tester.pumpAndSettle();
  });

  testWidgets('a refused Add from the share question says why', (tester) async {
    await open(tester);
    controller.addError = 'Only 0 more photos fit (limit 100).';
    await review(tester, _twoPhotos());

    controller.offerShare(['n1.jpg']);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.added, [
      ['n1.jpg'],
    ]);
    expect(find.text('Only 0 more photos fit (limit 100).'), findsOneWidget);
  });

  testWidgets('+ shows a spinner and is disabled while adding', (tester) async {
    await open(tester);
    await review(tester, _twoPhotos());
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controller.adding.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    final spinner = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    // The spinner never settles, so pump a fixed time.
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Take a photo'), findsNothing);

    controller.adding.value = false;
    await tester.pumpAndSettle();
    expect(spinner, findsNothing);
  });

  testWidgets('the out-of-stock sheet uses the dark themed surface', (
    tester,
  ) async {
    await open(tester);
    final picked = showOutOfStockSheet(Get.context!, count: 2);
    await tester.pumpAndSettle();

    expect(find.text('2 items are out of stock'), findsOneWidget);
    final surface = surfaceAbove(tester, find.text('2 items are out of stock'));
    expect(surface, AppScheme.dark.fg);
    expect(surface, darkTheme.colorScheme.surface);
    final sheetColours = [
      for (final e
          in find
              .descendant(
                of: find.byType(OutOfStockSheet),
                matching: find.byType(Material),
              )
              .evaluate())
        (e.widget as Material).color,
      for (final e
          in find
              .descendant(
                of: find.byType(OutOfStockSheet),
                matching: find.byType(Container),
              )
              .evaluate())
        if ((e.widget as Container).decoration case BoxDecoration(:final color))
          color,
    ];
    expect(sheetColours, isNot(contains(Colors.white)));

    await tester.tap(find.text('Include, no colour'));
    await tester.pumpAndSettle();
    expect(await picked, OutOfStockChoice.includePlain);
  });

  testWidgets('more than 100 photos goes to start, which refuses them', (
    tester,
  ) async {
    await open(tester, paths: List.generate(101, (i) => 'p$i.jpg'));
    expect(controller.starts.single, hasLength(101));
  });

  testWidgets('review: counts, and Generate file in the remembered format', (
    tester,
  ) async {
    await open(tester, remembered: SheetFormat.both);
    expect(controller.format.value, SheetFormat.both);
    controller.onSheet = 1;
    controller.phase.value = StockSheetPhase.reviewing;
    await tester.pumpAndSettle();

    expect(find.text('Review photos'), findsOneWidget);
    expect(find.text('0 photos · 1 in the file'), findsOneWidget);
    await tester.tap(find.text('Generate file · 1 photo'));
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

    // Nothing starts until the user answers the screen's question.
    expect(
      find.text('Add these 3 photos to the list, or start again?'),
      findsOneWidget,
    );
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
    expect(find.text('Generating the file…'), findsOneWidget);
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
    expect(find.text('Nothing to put in a file.'), findsOneWidget);
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
    // The photos on the sheet, not every photo shared.
    controller.total.value = 11;
    controller.onSheet = 8;
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
