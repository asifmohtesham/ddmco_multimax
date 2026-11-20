import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';
import 'package:multimax/app/modules/stock_sheet/model/ageing_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:share_plus/share_plus.dart';

/// A checksum-valid EAN-8 for a seven-digit item code.
String _ean(String seven) {
  var sum = 0;
  for (var i = 0; i < 7; i++) {
    sum += int.parse(seven[i]) * (i.isEven ? 3 : 1);
  }
  return '$seven${(10 - sum % 10) % 10}';
}

const _a = '1000001';
const _b = '1000002';
const _rack = 'KA-WH-DXB1-21A';

const _ageingA = ItemAgeing(
  availableQty: 384,
  averageAge: 120.5,
  earliest: 400,
  latest: 3,
  buckets: [(label: '0 - 90', qty: 300), (label: '721 - Above', qty: 84)],
);

/// Remembers the format in memory, like the StorageService-backed store.
class _MemoryFormatStore implements SheetFormatStore {
  SheetFormat? saved;

  @override
  SheetFormat read() => saved ?? SheetFormat.excel;

  @override
  void write(SheetFormat f) => saved = f;
}

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> m = {};
  T? read<T>(String key) => m[key] as T?;
  Future<void> write(String key, dynamic value) async => m[key] = value;
  bool hasData(String key) => m.containsKey(key);
  Future<void> remove(String key) async => m.remove(key);
}

class _FakeDecoder extends PhotoDecoder {
  _FakeDecoder(this.codes, {this.unsupported = false});
  final Map<String, List<String>?> codes;
  final bool unsupported;
  final Set<String> throwFor = {};
  int calls = 0;
  final decoded = <String>[];
  bool disposed = false;

  /// When set, every whole-photo read waits for it.
  Completer<void>? gate;

  /// What zooming in on a photo gives; what the quick pass gave when absent.
  final Map<String, List<String>?> zoomed = {};

  /// Every photo zoomed in on, in order.
  final zooms = <String>[];

  /// When set, every zoom waits for it.
  Completer<void>? zoomGate;

  /// Every zoom told to stop, in order.
  final stops = <String>[];

  /// Every read, in order: `whole:<path>` or `zoom:<path>`.
  final log = <String>[];

  @override
  Future<List<String>?> readWhole(String path) async {
    calls++;
    decoded.add(path);
    log.add('whole:$path');
    await gate?.future;
    if (unsupported) throw UnsupportedError('no');
    if (throwFor.contains(path)) throw Exception('boom');
    return codes[path];
  }

  @override
  Future<List<String>?> zoomIn(
    String path, {
    required List<String> whole,
    bool Function()? stopped,
  }) async {
    zooms.add(path);
    log.add('zoom:$path');
    await zoomGate?.future;
    if (stopped?.call() == true) {
      stops.add(path);
      return null;
    }
    return zoomed[path] ?? whole;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeProvider extends StockSheetProvider {
  _FakeProvider({
    this.stock = const {},
    this.known = const [_a, _b],
    this.images = const {},
  });
  final Map<String, double> stock;
  final List<String> known;

  /// Item code → its `image` field.
  final Map<String, String> images;
  Object? stockError;
  int stockCalls = 0;

  /// Every code list passed to [fetchItems] and [fetchFinishedGoodsStock].
  final itemRequests = <List<String>>[];
  final stockRequests = <List<String>>[];

  /// When set, the next Item call throws it.
  Object? itemsError;

  /// When set, the Item call waits for it.
  Completer<void>? itemsGate;

  /// When set, only the next Item call waits for it.
  Completer<void>? itemsGateOnce;

  /// When set, the stock call waits for it.
  Completer<void>? stockGate;

  /// Item code → its Stock Ageing rows; an item not here has none.
  final ageing = <String, List<ItemAgeing>>{};

  /// Every item code passed to [fetchStockAgeing], in order.
  final ageingRequests = <String>[];

  /// When set, every Stock Ageing call throws it.
  Object? ageingError;

  /// When set, the Stock Ageing call waits for it.
  Completer<void>? ageingGate;

  @override
  Future<List<ItemAgeing>> fetchStockAgeing(String itemCode) async {
    ageingRequests.add(itemCode);
    await ageingGate?.future;
    final error = ageingError;
    if (error != null) throw error;
    return ageing[itemCode] ?? const [];
  }

  @override
  Future<Map<String, ItemInfo>> fetchItems(List<String> codes) async {
    itemRequests.add(List.of(codes));
    await itemsGate?.future;
    final once = itemsGateOnce;
    itemsGateOnce = null;
    await once?.future;
    final error = itemsError;
    if (error != null) {
      itemsError = null;
      throw error;
    }
    return {
      for (final c in codes.where(known.contains))
        c: ItemInfo(itemCode: c, itemName: 'Item $c', image: images[c]),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(
    List<String> codes,
  ) async {
    stockCalls++;
    stockRequests.add(List.of(codes));
    await stockGate?.future;
    final error = stockError;
    if (error != null) {
      stockError = null;
      throw error;
    }
    return [
      for (final c in codes)
        {'item_code': c, 'bal_qty': stock[c] ?? 0, 'rack': _rack},
    ];
  }
}

class _ImageProvider extends _FakeProvider {
  final requests = <String>[];
  Completer<Uint8List> download = Completer<Uint8List>();

  @override
  Future<Uint8List> fetchImage(String url) {
    requests.add(url);
    return download.future;
  }
}

void main() {
  late Directory tmp;
  late List<List<XFile>> shared;
  late List<StockSheetDocument> pdfDocs;

  /// Fixed fingerprints by path; any other path is its own content.
  late Map<String, String> fingerprints;

  Future<Uint8List?> Function(String)? thumbOverride;

  /// When set, the PDF writer waits for it.
  Completer<void>? pdfGate;

  /// When set, the next share throws it.
  Object? shareError;

  /// When set, only the next fingerprinting waits for it.
  Completer<void>? fingerprintGateOnce;

  /// When set, the PDF writer throws it.
  Object? pdfError;

  late List<(String, Uint8List)> saveCalls;
  late List<bool> saveAnswers;
  Object? saveError;
  Completer<void>? saveGate;

  setUp(() async {
    saveCalls = [];
    saveAnswers = [];
    saveError = null;
    saveGate = null;
    tmp = await Directory.systemTemp.createTemp('stock_sheet_ctrl');
    shared = [];
    pdfDocs = [];
    fingerprints = {};
    thumbOverride = null;
    pdfGate = null;
    shareError = null;
    pdfError = null;
    fingerprintGateOnce = null;
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  StockSheetController make(
    _FakeDecoder decoder,
    _FakeProvider provider, {
    SheetFormatStore? store,
    Future<List<String>> Function()? extraRoots,
    Future<void> Function()? clearPickerFiles,
    Future<Uint8List?> Function(String url)? itemThumbnail,
  }) => StockSheetController(
    itemThumbnail: itemThumbnail ?? (url) async => null,
    clearPickerFiles: clearPickerFiles ?? () async {},
    formatStore: store ?? _MemoryFormatStore(),
    decoderFactory: () => decoder,
    provider: provider,
    saveFile: (name, bytes) async {
      saveCalls.add((name, bytes));
      await saveGate?.future;
      final error = saveError;
      if (error != null) throw error;
      final answers = saveAnswers;
      return answers.isEmpty ? true : answers.removeAt(0);
    },
    shareFiles: (f) async {
      final error = shareError;
      if (error != null) {
        shareError = null;
        throw error;
      }
      shared.add(f);
    },
    now: () => DateTime(2026, 11, 17, 9, 5),
    fingerprint: (paths) async {
      final once = fingerprintGateOnce;
      fingerprintGateOnce = null;
      await once?.future;
      return {for (final path in paths) path: fingerprints[path] ?? 'fp:$path'};
    },
    tempDir: () async => tmp,
    extraCleanupRoots: extraRoots ?? () async => const [],
    writePdf: (doc) async {
      await pdfGate?.future;
      final error = pdfError;
      if (error != null) throw error;
      pdfDocs.add(doc);
      return Uint8List.fromList([1, 2, 3]);
    },
    makeThumbnail:
        thumbOverride ??
        (p) async =>
            Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4))),
  );

  test('Item Image downloads are shared and cached until reset', () async {
    const url = '/files/item.jpg';
    final provider = _ImageProvider();
    final c = make(_FakeDecoder({}), provider);
    final bytes = img.encodeJpg(img.Image(width: 4, height: 4));

    final failed = c.itemImage(url);
    expect(c.itemImage(url), same(failed));
    expect(provider.requests, [url]);
    final failure = expectLater(failed, throwsException);
    provider.download.completeError(Exception('offline'));
    await failure;
    expect(c.cachedItemImage(url), isNull);

    provider.download = Completer<Uint8List>();
    final retried = c.itemImage(url);
    provider.download.complete(bytes);
    expect(await retried, same(bytes));
    expect(c.cachedItemImage(url), same(bytes));
    expect(await c.itemImage(url), same(bytes));
    expect(provider.requests, [url, url]);

    c.reset();
    expect(c.cachedItemImage(url), isNull);
    provider.download = Completer<Uint8List>();
    final oldDownload = provider.download;
    final oldRequest = c.itemImage(url);
    c.reset();
    provider.download = Completer<Uint8List>();
    final newRequest = c.itemImage(url);
    oldDownload.complete(bytes);
    await oldRequest;
    expect(c.cachedItemImage(url), isNull);
    expect(c.itemImage(url), same(newRequest));
    provider.download.complete(bytes);
    expect(await newRequest, same(bytes));
    expect(c.cachedItemImage(url), same(bytes));
  });

  /// Lets the reading loop run until every row is settled (or it can go no
  /// further, e.g. stuck behind an error).
  Future<void> settled(StockSheetController c) async {
    for (var i = 0; i < 50 && c.reading.value; i++) {
      await pumpEventQueue();
    }
  }

  /// Reads [paths], then makes the sheet in [format] from the review as is.
  Future<void> run(
    StockSheetController c,
    List<String> paths,
    SheetFormat format,
  ) async {
    await c.start(paths);
    await settled(c);
    await c.makeSheet(format);
  }

  List<String> reviewPaths(StockSheetController c) =>
      c.review.map((e) => e.path).toList();

  /// Waits for the clean-up after onClose, which deletes files for real.
  Future<void> untilGone(List<File> files) async {
    for (var i = 0; i < 200 && files.any((f) => f.existsSync()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('reading in two rounds', () {
    final eanA = _ean(_a);
    final eanB = _ean(_b);

    test(
      'the list opens with a row per photo before anything is read',
      () async {
        final decoder = _FakeDecoder({
          'p1': [eanA],
          'p2': [eanB],
        })..gate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        unawaited(c.start(['p1', 'p2']));
        await pumpEventQueue();
        expect(c.phase.value, StockSheetPhase.reviewing);
        expect(c.review.map((e) => e.number), [1, 2]);
        expect(c.review.map((e) => e.stage), [
          ReadStage.reading,
          ReadStage.notRead,
        ]);
        expect(c.reading.value, isTrue);
        decoder.gate!.complete();
      },
    );

    test(
      'every photo gets the quick pass before any is zoomed in on',
      () async {
        final decoder =
            _FakeDecoder({
                'p1': const [],
                'p2': [eanA],
                'p3': const [],
              })
              ..zoomed.addAll({
                'p1': [eanB],
                'p3': const [],
              });
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2', 'p3']);
        await settled(c);
        expect(decoder.log, [
          'whole:p1',
          'whole:p2',
          'whole:p3',
          'zoom:p1',
          'zoom:p3',
        ]);
        expect(c.review.map((e) => e.resolved), [
          true,
          true,
          false,
        ]); // p3: "No recognised code"
        expect(c.review.every((e) => e.settled), isTrue);
        expect(c.reading.value, isFalse);
      },
    );

    test(
      'round one\'s items are asked for in one batch, a zoomed photo\'s on its own',
      () async {
        final provider = _FakeProvider();
        final decoder = _FakeDecoder({
          'p1': [eanA],
          'p2': const [],
        })..zoomed['p2'] = [eanB];
        final c = make(decoder, provider);
        await c.start(['p1', 'p2']);
        await settled(c);
        expect(provider.itemRequests, [
          [_a],
          [_b],
        ]);
        expect(provider.stockRequests, [
          [_a],
          [_b],
        ]);
      },
    );

    test(
      'the same item in two photos is asked for once and both rows settle',
      () async {
        final provider = _FakeProvider();
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
            'p2': const [],
          })..zoomed['p2'] = [eanA],
          provider,
        );
        await c.start(['p1', 'p2']);
        await settled(c);
        expect(provider.itemRequests, [
          [_a],
        ]);
        expect(c.review.map((e) => e.items.single.info.itemCode), [_a, _a]);
      },
    );

    test(
      'a sheet of labels stays one row until zoomed in on, then becomes its rows in place',
      () async {
        final decoder =
            _FakeDecoder({
                'p1': [eanA, eanB],
                'p2': [eanA],
              })
              ..zoomGate = Completer<void>()
              ..zoomed['p1'] = [eanB, eanA];
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        expect(c.review, hasLength(2));
        expect(c.review.first.stage, ReadStage.zooming);
        expect(
          c.review.first.codes,
          hasLength(2),
        ); // "Photo 1 · 2 items so far"
        decoder.zoomGate!.complete();
        await settled(c);
        expect(c.review.map((e) => e.items.single.info.itemCode), [
          _b,
          _a,
          _a,
        ]); // p1's rows first, in reading order
        expect(c.review.take(2).every((e) => e.path == 'p1'), isTrue);
      },
    );

    test('an unreadable photo is settled without a zoom', () async {
      final decoder = _FakeDecoder({'p1': null});
      final c = make(decoder, _FakeProvider());
      await c.start(['p1']);
      await settled(c);
      expect(c.review.single.decodeFailed, isTrue);
      expect(decoder.zooms, isEmpty);
    });

    test(
      'a stock batch that cannot reach the ERP leaves its rows unchecked and reading goes on',
      () async {
        final provider = _FakeProvider()..stockError = Exception('offline');
        final decoder = _FakeDecoder({
          'p1': [eanA],
          'p2': const [],
        })..zoomed['p2'] = const [];
        final c = make(decoder, provider);
        await c.start(['p1', 'p2']);
        await settled(c);
        expect(c.phase.value, StockSheetPhase.reviewing);
        expect(c.review.first.unchecked, isTrue);
        expect(decoder.zooms, ['p2']);
        provider.stockError = null;
        expect(await c.retryCheck(), isNull);
        expect(c.review.first.resolved, isTrue);
      },
    );

    test(
      'a new start during a read waits for it and drops its answer',
      () async {
        final decoder = _FakeDecoder({
          'p1': [eanA],
          'q1': [eanB],
        })..gate = Completer<void>();
        final provider = _FakeProvider();
        final c = make(decoder, provider);
        await c.start(['p1']);
        await pumpEventQueue();
        expect(c.review.single.stage, ReadStage.reading);

        await c.start(['q1']);
        await pumpEventQueue();
        // q1 waits for the read in hand: never two reads at once.
        expect(decoder.log, ['whole:p1']);
        expect(c.review.single.path, 'q1');
        expect(c.review.single.stage, ReadStage.notRead);

        decoder.gate!.complete();
        await settled(c);
        expect(decoder.log, ['whole:p1', 'whole:q1']);
        expect(c.review.single.items.single.info.itemCode, _b);
        expect(c.thumbnails.keys, ['q1']);
        expect(provider.itemRequests, [
          [_b],
        ]);
      },
    );

    test(
      'a late "no access" for rows no longer listed leaves the file screen alone',
      () async {
        final provider = _FakeProvider(stock: {_a: 1, _b: 1});
        final c = make(
          _FakeDecoder({
            'p0': [eanB],
            'p1': [eanA],
          }),
          provider,
        );
        await c.start(['p0']);
        await settled(c);
        provider
          ..stockGate = Completer<void>()
          ..stockError = const StockAccessDenied();
        expect(await c.addPhotos(['p1']), isNull);
        await pumpEventQueue();
        expect(c.review.last.stage, ReadStage.checkingStock);

        c.removeAt(1);
        await c.makeSheet(SheetFormat.excel);
        expect(c.phase.value, StockSheetPhase.done);

        provider.stockGate!.complete();
        await pumpEventQueue();
        expect(c.phase.value, StockSheetPhase.done);
        expect(c.errorMessage.value, isNull);
        expect(c.files, hasLength(1));
      },
    );

    test(
      'a late "no access" for rows no longer listed leaves the review alone',
      () async {
        final provider = _FakeProvider()
          ..stockGate = Completer<void>()
          ..stockError = const StockAccessDenied();
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
          }),
          provider,
        );
        await c.start(['p1']);
        await pumpEventQueue();
        expect(c.review.single.stage, ReadStage.checkingStock);

        c.removeAt(0);
        provider.stockGate!.complete();
        await pumpEventQueue();
        expect(c.phase.value, StockSheetPhase.reviewing);
        expect(c.errorMessage.value, isNull);
      },
    );

    test('no access to stock levels still ends in the error state', () async {
      final provider = _FakeProvider()..stockError = const StockAccessDenied();
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
        }),
        provider,
      );
      await c.start(['p1']);
      await settled(c);
      expect(c.phase.value, StockSheetPhase.error);
      expect(c.errorMessage.value, StockSheetController.noAccessMessage);
    });
  });

  group('rows stay live while reading', () {
    final eanA = _ean(_a);
    final eanB = _ean(_b);

    test(
      'removing the photo being zoomed in on stops it and starts the next',
      () async {
        final decoder = _FakeDecoder({'p1': const [], 'p2': const []})
          ..zoomGate = Completer<void>()
          ..zoomed.addAll({
            'p1': [eanA],
            'p2': [eanB],
          });
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        expect(c.review.first.stage, ReadStage.zooming);
        final removed = c.removeAt(0)!;
        decoder.zoomGate!.complete();
        await settled(c);
        expect(decoder.zooms, ['p1', 'p2']);
        expect(decoder.stops, ['p1']);
        expect(c.review.single.path, 'p2');
        expect(c.review.single.items.single.info.itemCode, _b);
        expect(removed.path, 'p1');
      },
    );

    test(
      'Undo puts the photo back to wait its turn by its place in the list',
      () async {
        final decoder = _FakeDecoder({'p1': const [], 'p2': const []})
          ..zoomGate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        final removed = c.removeAt(0)!;
        c.restore(removed, 0);
        expect(c.review.first.stage, ReadStage.waiting);
        decoder.zoomGate!.complete();
        await settled(c);
        // Stopped, then read afresh before p2: it is first in the list.
        expect(decoder.zooms, ['p1', 'p1', 'p2']);
        // The stop belonged to the first attempt only.
        expect(decoder.stops, ['p1']);
        expect(c.review.map((e) => e.path), ['p1', 'p2']);
      },
    );

    test(
      'Undo of a photo in its quick pass puts it back as not read yet',
      () async {
        final decoder = _FakeDecoder({
          'p1': [eanA],
          'p2': [eanB],
        })..gate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        expect(c.review.first.stage, ReadStage.reading);
        final removed = c.removeAt(0)!;
        c.restore(removed, 0);
        expect(c.review.first.stage, ReadStage.notRead);
        decoder.gate!.complete();
        await settled(c);
        // The read in hand is dropped; the photo is read afresh, in its place.
        expect(decoder.log, ['whole:p1', 'whole:p1', 'whole:p2']);
        expect(c.review.map((e) => e.path), ['p1', 'p2']);
        expect(c.review.map((e) => e.items.single.info.itemCode), [_a, _b]);
        expect(c.reading.value, isFalse);
      },
    );

    test(
      'Undo puts a row back beside its neighbour, never inside another photo\'s rows',
      () async {
        final decoder = _FakeDecoder({
          'sheet': [eanA, eanB],
          'bad': null,
          'p3': [eanA],
        })..zoomGate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        await c.start(['sheet', 'bad', 'p3']);
        await pumpEventQueue();
        expect(c.review.first.stage, ReadStage.zooming);
        final removed = c.removeAt(1)!;
        expect(removed.path, 'bad');

        // Meanwhile the sheet photo above becomes its two rows.
        decoder.zoomGate!.complete();
        await settled(c);
        expect(reviewPaths(c), ['sheet', 'sheet', 'p3']);

        c.restore(removed, 1);
        expect(reviewPaths(c), ['sheet', 'sheet', 'bad', 'p3']);
      },
    );

    test('Undo of one row of a photo puts it back in its place', () async {
      final c = make(
        _FakeDecoder({
          'sheet': [eanA, eanB],
          'p2': [eanA],
        }),
        _FakeProvider(),
      );
      await c.start(['sheet', 'p2']);
      await settled(c);
      final ids = c.review.map((e) => e.id).toList();
      final removed = c.removeAt(0)!;
      c.restore(removed, 0);
      expect(c.review.map((e) => e.id), ids);
      final second = c.removeAt(1)!;
      c.reorder(1, 0); // p2 to the top: p2, sheet#0
      c.restore(second, 1);
      expect(c.review.map((e) => e.id), [ids[2], ids[0], ids[1]]);
    });

    test('a photo removed before its turn is never read', () async {
      final decoder = _FakeDecoder({'p1': const [], 'p2': const []})
        ..zoomGate = Completer<void>();
      final c = make(decoder, _FakeProvider());
      await c.start(['p1', 'p2']);
      await pumpEventQueue();
      c.removeAt(1);
      decoder.zoomGate!.complete();
      await settled(c);
      expect(decoder.zooms, ['p1']);
    });

    test(
      'a row dragged up is zoomed in on sooner; the photo in hand finishes first',
      () async {
        final decoder = _FakeDecoder({
          'p1': const [],
          'p2': const [],
          'p3': const [],
        })..zoomGate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2', 'p3']);
        await pumpEventQueue();
        c.reorder(2, 0); // p3 to the top while p1 is being zoomed in on
        decoder.zoomGate!.complete();
        await settled(c);
        expect(decoder.zooms, ['p1', 'p3', 'p2']);
      },
    );

    test(
      'a row moved while it is zoomed in on gets its answer at its new place',
      () async {
        final decoder =
            _FakeDecoder({
                'p1': const [],
                'p2': [eanB],
                'p3': [eanB],
              })
              ..zoomGate = Completer<void>()
              ..zoomed['p1'] = [eanA];
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2', 'p3']);
        await pumpEventQueue();
        expect(c.review.first.stage, ReadStage.zooming);
        c.reorder(0, 3); // p1 to the end: p2, p3, p1
        c.removeAt(0); // p2 goes: p3, p1
        decoder.zoomGate!.complete();
        await settled(c);
        expect(c.review.map((e) => e.path), ['p3', 'p1']);
        expect(c.review.map((e) => e.items.single.info.itemCode), [_b, _a]);
      },
    );

    test(
      'a row removed while its stock is being checked settles when put back',
      () async {
        final provider = _FakeProvider()..stockGate = Completer<void>();
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
          }),
          provider,
        );
        await c.start(['p1']);
        await pumpEventQueue();
        expect(c.review.single.stage, ReadStage.checkingStock);
        final removed = c.removeAt(0)!;
        provider.stockGate!.complete();
        await pumpEventQueue();
        c.restore(removed, 0);
        await settled(c);
        expect(c.review.single.resolved, isTrue);
        expect(provider.itemRequests, hasLength(1));
      },
    );

    test(
      'starting again in the middle of a zoom writes nothing into the new review',
      () async {
        final decoder =
            _FakeDecoder({
                'p1': const [],
                'q1': [eanB],
              })
              ..zoomGate = Completer<void>()
              ..zoomed['p1'] = [eanA];
        final c = make(decoder, _FakeProvider());
        await c.start(['p1']);
        await pumpEventQueue();
        unawaited(c.start(['q1']));
        decoder.zoomGate!.complete();
        await settled(c);
        expect(c.review.map((e) => e.path), ['q1']);
      },
    );

    test(
      'closing in the middle of a zoom stops it; the decoder goes once it returns',
      () async {
        final decoder = _FakeDecoder({'p1': const []})
          ..zoomGate = Completer<void>()
          ..zoomed['p1'] = [eanA];
        final c = make(decoder, _FakeProvider());
        await c.start(['p1']);
        await pumpEventQueue();
        expect(c.review.single.stage, ReadStage.zooming);

        c.onClose();
        await pumpEventQueue();
        // The read in hand is not cut off under the platform's feet.
        expect(decoder.disposed, isFalse);

        decoder.zoomGate!.complete();
        await pumpEventQueue();
        expect(decoder.stops, ['p1']);
        expect(decoder.disposed, isTrue);
        expect(c.review.single.items, isEmpty);
      },
    );

    test(
      'a "no access" from the last review\'s batch does not fail the new one',
      () async {
        final provider = _FakeProvider(stock: {_a: 1})
          ..stockGate = Completer<void>()
          ..stockError = const StockAccessDenied();
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
            'q1': [eanA],
          }),
          provider,
        );
        await c.start(['p1']);
        await pumpEventQueue();
        await c.start(['q1']);
        await pumpEventQueue();
        expect(provider.stockRequests, [
          [_a],
          [_a],
        ]);

        // The old batch fails (its error is used up); the new one answers.
        provider.stockGate!.complete();
        await settled(c);
        expect(c.phase.value, StockSheetPhase.reviewing);
        expect(c.errorMessage.value, isNull);
        expect(c.review.single.path, 'q1');
        expect(c.review.single.items.single.stock!.total, 1);
      },
    );

    test('every photo removed while reading ends the reading', () async {
      final decoder = _FakeDecoder({'p1': const []})
        ..zoomGate = Completer<void>();
      final c = make(decoder, _FakeProvider());
      await c.start(['p1']);
      await pumpEventQueue();
      c.removeAt(0);
      decoder.zoomGate!.complete();
      await settled(c);
      expect(c.review, isEmpty);
      expect(c.reading.value, isFalse);
      expect(c.sheetItemCount, 0);
    });

    test(
      'photos added during reading join the list and get their quick pass before the next zoom',
      () async {
        final decoder = _FakeDecoder({
          'p1': const [],
          'p2': const [],
          'n1': [eanA],
        })..zoomGate = Completer<void>();
        final c = make(decoder, _FakeProvider());
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        expect(await c.addPhotos(['n1']), isNull);
        expect(c.review.last.number, 3);
        decoder.zoomGate!.complete();
        await settled(c);
        expect(decoder.log, [
          'whole:p1',
          'whole:p2',
          'zoom:p1',
          'whole:n1',
          'zoom:p2',
        ]);
      },
    );

    test('photo numbers never repeat within a review', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(['p1', 'p2']);
      await settled(c);
      expect(c.review.map((e) => e.number), [1, 2]);

      final removed = c.removeAt(1)!;
      expect(removed.number, 2);
      expect(await c.addPhotos(['p3']), isNull);
      c.restore(removed, 1);
      await settled(c);

      final numbers = c.review.map((e) => e.number).toList();
      expect(numbers.toSet(), hasLength(3));
      expect(numbers.toSet(), {1, 2, 3});
      expect(c.review.singleWhere((e) => e.path == 'p2').number, 2);
      expect(c.review.singleWhere((e) => e.path == 'p3').number, 3);

      await c.start(['q1']);
      expect(c.review.single.number, 1);
    });

    test('Generate file does nothing until every photo is read', () async {
      final decoder =
          _FakeDecoder({
              'p1': [eanA],
              'p2': const [],
            })
            ..zoomGate = Completer<void>()
            ..zoomed['p2'] = [eanB];
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
      await c.start(['p1', 'p2']);
      await pumpEventQueue();
      expect(c.review.first.resolved, isTrue);
      expect(c.review.last.stage, ReadStage.zooming);
      expect(c.sheetItemCount, 1);

      await c.makeSheet(SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.result.value, isNull);
      expect(c.files, isEmpty);
      expect(shared, isEmpty);

      decoder.zoomGate!.complete();
      await settled(c);
      await c.makeSheet(SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.done);
      expect(c.result.value!.rows.map((r) => r.photoPath), ['p1', 'p2']);
      expect(shared.single, hasLength(1));
    });
  });

  test('more than 100 photos is refused and nothing is decoded', () async {
    final decoder = _FakeDecoder({});
    final c = make(decoder, _FakeProvider());
    await c.start(List.generate(101, (i) => 'p$i.jpg'));
    await settled(c);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      'Share up to 100 photos at a time (you shared 101).',
    );
    expect(decoder.calls, 0);
    expect(c.canRetry, isFalse);
  });

  test('start reads and checks, then waits in review in share order', () async {
    final decoder = _FakeDecoder({
      'known.jpg': [_ean(_a)],
      'out.jpg': [_ean(_b)],
      'bad.jpg': null,
    });
    final provider = _FakeProvider(stock: {_a: 4});
    final c = make(decoder, provider);
    await c.start(['known.jpg', 'out.jpg', 'bad.jpg']);
    await settled(c);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.busy.value, isFalse);
    expect(reviewPaths(c), ['known.jpg', 'out.jpg', 'bad.jpg']);
    expect(c.review.map((e) => e.included), [true, true, false]);
    expect(c.review[2].decodeFailed, isTrue);
    final known = c.review[0].items.single;
    expect(known.info.itemName, 'Item $_a');
    expect(known.stock!.total, 4);
    expect(known.stock!.racks, [const RackQty(rack: _rack, qty: 4)]);
    expect(c.review[1].items.single.stock!.outOfStock, isTrue);
    expect(c.sheetPhotoCount, 2);
    expect(provider.stockCalls, 1);
    // Nothing is written or shared until Generate file.
    expect(shared, isEmpty);
    expect(c.result.value, isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('all in stock builds at once: one xlsx, or two for both', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 5});
    final c = make(decoder, provider);
    await run(c, ['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(
      shared.single.single.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(File(shared.single.single.path).existsSync(), isTrue);
    expect(c.review.single.stage, ReadStage.settled);
    expect(c.reading.value, isFalse);
    expect(c.busy.value, isFalse);

    await run(c, ['a.jpg'], SheetFormat.both);
    expect(shared.last.map((f) => f.name), [
      'Items-20261117-0905.xlsx',
      'Items-20261117-0905.pdf',
    ]);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 0 out of stock',
    );
    expect(pdfDocs.single.title, 'Items');
    expect(pdfDocs.single.showStatus, isFalse);

    final path = shared.last.first.path;
    c.onClose();
    expect(File(path).existsSync(), isFalse);
  });

  test('makeSheet(pdf) makes only a PDF and is remembered', () async {
    final store = _MemoryFormatStore();
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}), store: store);
    c.onInit();
    expect(c.format.value, SheetFormat.excel);

    await run(c, ['a.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.map((f) => f.name), ['Items-20261117-0905.pdf']);
    expect(shared.single.single.mimeType, 'application/pdf');
    expect(c.format.value, SheetFormat.pdf);
    expect(store.saved, SheetFormat.pdf);

    final next = make(_FakeDecoder({}), _FakeProvider(), store: store);
    next.onInit();
    expect(next.format.value, SheetFormat.pdf);
  });

  test('the rows follow the review order', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    await settled(c);
    c.reorder(0, 2);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);

    await c.makeSheet(SheetFormat.pdf);
    expect(pdfDocs.single.rows.map((r) => r.barcode), [_ean(_b), _ean(_a)]);
    expect(pdfDocs.single.rows.map((r) => r.photoPath), ['b.jpg', 'a.jpg']);
  });

  test('reorder, then a switch, keeps the order', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    await settled(c);
    c.reorder(0, 2);
    c.setIncluded(1, false);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);
    expect(c.review.map((e) => e.included), [true, false]);

    c.setIncluded(1, true);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);
    expect(c.review.map((e) => e.included), [true, true]);
  });

  test('a switched-off out-of-stock photo asks nothing', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    await settled(c);
    c.setIncluded(1, false);

    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.map((r) => r.barcode), [_ean(_a)]);
    expect(c.result.value!.rows, hasLength(1));
    // A photo the user switched off is in neither list.
    expect(c.result.value!.unresolved, isEmpty);
  });

  test('the subtitle counts only the photos in the file', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    await settled(c);
    c.setIncluded(0, false);
    expect(c.sheetPhotoCount, 1);

    await c.makeSheet(SheetFormat.pdf);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 0 out of stock',
    );
  });

  test(
    'review edits and Generate file are ignored outside the review',
    () async {
      final store = _MemoryFormatStore();
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final c = make(
        decoder,
        _FakeProvider(stock: {_a: 1, _b: 1}),
        store: store,
      );

      // Idle: nothing to edit, nothing to make.
      c.reorder(0, 1);
      c.setIncluded(0, false);
      await c.makeSheet(SheetFormat.pdf);
      expect(c.phase.value, StockSheetPhase.idle);
      expect(store.saved, isNull);

      await run(c, ['a.jpg', 'b.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.done);
      final before = c.review.toList();
      c.reorder(0, 2);
      c.setIncluded(0, false);
      c.setIncluded(1, false);
      expect(c.review, orderedEquals(before));
      await c.makeSheet(SheetFormat.pdf);
      expect(shared, hasLength(1));
      expect(store.saved, SheetFormat.excel);
    },
  );

  test('Generate file with every photo switched off does nothing', () async {
    final store = _MemoryFormatStore();
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}), store: store);
    await c.start(['a.jpg', 'bad.jpg']);
    await settled(c);
    c.setIncluded(0, false);
    expect(c.sheetPhotoCount, 0);

    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(store.saved, isNull);
    expect(c.format.value, SheetFormat.excel);
    expect(shared, isEmpty);
  });

  test('out of stock asks; dismissing returns to the review intact', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg']);
    await settled(c);
    final before = c.review.toList();
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    expect(c.result.value!.outOfStockCount, 1);

    await c.chooseOutOfStock(null);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.result.value, isNull);
    expect(c.review, orderedEquals(before));
    expect(shared, isEmpty);
    expect(tmp.listSync(), isEmpty);
  });

  test('leaveOut drops red rows and hides the status column', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 3}));
    await run(c, ['a.jpg', 'b.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.every((r) => !r.outOfStock), isTrue);
    expect(pdfDocs.single.rows, hasLength(1));
    expect(pdfDocs.single.showStatus, isFalse);
    // The out-of-stock row is not in the file, so neither its count nor its
    // photo is.
    expect(pdfDocs.single.subtitle, '17/11/2026 09:05 · 1 photo · 1 item');
  });

  test('leaving out every item goes back to the review and says why', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 2}));
    await c.start(['a.jpg', 'b.jpg']);
    await settled(c);
    c.setIncluded(1, false);
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);

    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, 'Every photo in the file is out of stock.');
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(shared, isEmpty);
    expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
    expect(c.busy.value, isFalse);
  });

  test('plural counts in the subtitle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a), _ean(_b)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['a.jpg', 'b.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includePlain);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 2 photos · 3 items · 2 out of stock',
    );
  });

  test('includeRed highlights and shows status', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await run(c, ['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includeRed);
    expect(pdfDocs.single.highlightOutOfStock, isTrue);
    expect(pdfDocs.single.showStatus, isTrue);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 1 out of stock',
    );
    await run(c, ['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includePlain);
    expect(pdfDocs.last.highlightOutOfStock, isFalse);
    expect(pdfDocs.last.showStatus, isTrue);
  });

  test('retry after a stock failure does not decode again', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 2})
      ..stockError = const StockAccessDenied();
    final c = make(decoder, provider);
    await c.start(['a.jpg']);
    await settled(c);
    expect(c.phase.value, StockSheetPhase.error);
    expect(c.errorMessage.value, "You don't have access to stock levels.");
    expect(c.canRetry, isTrue);
    expect(decoder.calls, 1);
    await c.retry();
    expect(decoder.calls, 1);
    expect(provider.stockCalls, 2);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, isNull);
    expect(reviewPaths(c), ['a.jpg']);
    expect(c.review.single.items.single.stock!.total, 2);
    expect(c.reading.value, isFalse);
    expect(c.canRetry, isFalse);

    // Retry belongs to the error screen only.
    await c.retry();
    expect(provider.stockCalls, 2);

    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared, hasLength(1));
  });

  test('an unreadable photo is listed and the run completes', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['bad.jpg', 'a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(
      c.result.value!.unresolved.single.reason,
      UnresolvedReason.unreadable,
    );
    expect(c.thumbnails.keys, containsAll(['bad.jpg', 'a.jpg']));
  });

  test('a 403 shows the access-denied text', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider()..stockError = const StockAccessDenied();
    final c = make(decoder, provider);
    await c.start(['a.jpg']);
    await settled(c);
    expect(c.phase.value, StockSheetPhase.error);
    expect(c.errorMessage.value, "You don't have access to stock levels.");
    expect(c.result.value, isNull);
    // The row waits for its stock; nothing reaches the review unchecked.
    expect(c.review.single.stage, ReadStage.checkingStock);
    expect(c.review.single.items, isEmpty);
  });

  test('UnsupportedError from the decoder gives the device message', () async {
    final decoder = _FakeDecoder({}, unsupported: true);
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg']);
    await settled(c);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Reading barcodes from photos isn't supported on this device.",
    );
    expect(decoder.calls, 1);
    expect(c.canRetry, isFalse);
    // One decoder for the controller's life, disposed with it.
    expect(decoder.disposed, isFalse);
    c.onClose();
    await pumpEventQueue();
    expect(decoder.disposed, isTrue);
  });

  test('start while busy is a no-op; reset clears when idle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    final first = c.start(['a.jpg']);
    expect(c.busy.value, isTrue);
    await c.start(['a.jpg']);
    await first;
    await settled(c);
    expect(decoder.calls, 1);
    await c.makeSheet(SheetFormat.excel);
    expect(shared, hasLength(1));

    c.reset();
    expect(c.phase.value, StockSheetPhase.idle);
    expect(c.result.value, isNull);
    expect(c.review, isEmpty);
    expect(c.files, isEmpty);
    expect(c.thumbnails, isEmpty);
    expect(c.total.value, 0);
  });

  test('a decoder exception marks only that photo unreadable', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    })..throwFor.add('bad.jpg');
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['bad.jpg', 'a.jpg']);
    await settled(c);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.review.map((e) => e.decodeFailed), [true, false]);
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(
      c.result.value!.unresolved.single.reason,
      UnresolvedReason.unreadable,
    );
    expect(decoder.calls, 2);
  });

  test('a thumbnail exception still completes the run', () async {
    thumbOverride = (_) async => throw Exception('thumb');
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.thumbnails, isEmpty);
  });

  test('a build failure returns to the review with the message', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    pdfError = Exception('no pdf');
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['a.jpg']);
    await settled(c);
    final before = c.review.toList();
    await c.makeSheet(SheetFormat.both);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, "Couldn't build the sheet. Try again.");
    expect(c.review, orderedEquals(before));
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect(shared, isEmpty);
    expect(c.busy.value, isFalse);

    // The next Generate file clears the message.
    pdfError = null;
    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared.single.single.name, 'Items-20261117-0905.pdf');
  });

  test('a share failure returns to the review with the message', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 1});
    shareError = Exception('no share sheet');
    final c = make(decoder, provider);
    await run(c, ['a.jpg'], SheetFormat.excel);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, StockSheetController.shareFailedMessage);
    expect(reviewPaths(c), ['a.jpg']);
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect(shared, isEmpty);

    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(provider.stockCalls, 1);
    expect(decoder.calls, 1);
  });

  test(
    'Share files shares again; a failure there stays on the result',
    () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final provider = _FakeProvider(stock: {_a: 1});
      final c = make(decoder, provider);
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(shared, hasLength(1));

      await c.shareAgain();
      expect(shared, hasLength(2));
      expect(shared.last.single.name, 'Items-20261117-0905.xlsx');
      expect(c.errorMessage.value, isNull);
      expect(c.sharing.value, isFalse);
      expect(provider.stockCalls, 1);

      shareError = Exception('again');
      await c.shareAgain();
      expect(c.errorMessage.value, StockSheetController.shareFailedMessage);
      expect(c.phase.value, StockSheetPhase.done);
      expect(File(c.files.single.path).existsSync(), isTrue);
      expect(c.sharing.value, isFalse);
    },
  );

  group('Download', () {
    Future<StockSheetController> both() async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1}),
      );
      await run(c, ['a.jpg'], SheetFormat.both);
      return c;
    }

    test('download saves each file in order with its name', () async {
      final c = await both();
      final message = await c.download();
      expect(saveCalls.map((e) => e.$1).toList(), [
        'Items-20261117-0905.xlsx',
        'Items-20261117-0905.pdf',
      ]);
      expect(saveCalls.every((e) => e.$2.isNotEmpty), isTrue);
      expect(message, 'Saved 2 files.');
    });

    test('one file returns "Saved <name>."', () async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1}),
      );
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(await c.download(), 'Saved Items-20261117-0905.xlsx.');
    });

    test(
      'cancelling the second dialog keeps the first and returns null',
      () async {
        final c = await both();
        saveAnswers = [true, false];
        expect(await c.download(), isNull);
        expect(saveCalls, hasLength(2));
      },
    );

    test('a saver error returns saveFailedMessage and stops', () async {
      final c = await both();
      saveError = Exception('disk');
      expect(await c.download(), StockSheetController.saveFailedMessage);
      expect(saveCalls, hasLength(1));
      expect(c.downloading.value, isFalse);
    });

    test('download while running or while sharing does nothing', () async {
      final c = await both();
      saveGate = Completer<void>();
      final first = c.download();
      await Future<void>.delayed(Duration.zero);
      expect(await c.download(), isNull);
      saveGate!.complete();
      expect(await first, 'Saved 2 files.');
      expect(saveCalls, hasLength(2));

      saveCalls.clear();
      c.sharing.value = true;
      expect(await c.download(), isNull);
      expect(saveCalls, isEmpty);
    });

    test('sharing does nothing while downloading', () async {
      final c = await both();
      final before = shared.length;
      saveGate = Completer<void>();
      final first = c.download();
      await Future<void>.delayed(Duration.zero);
      await c.shareAgain();
      expect(shared, hasLength(before));
      saveGate!.complete();
      await first;
    });

    test('downloading is true during the run and false after', () async {
      final c = await both();
      saveGate = Completer<void>();
      final run1 = c.download();
      await Future<void>.delayed(Duration.zero);
      expect(c.downloading.value, isTrue);
      saveGate!.complete();
      await run1;
      expect(c.downloading.value, isFalse);
    });
  });

  group('remembered format in StorageService', () {
    tearDown(Get.reset);

    test('missing or unknown reads as Excel; a choice round-trips', () {
      final box = _FakeBox();
      Get.put(StorageService.withStorage(box));
      const store = StorageSheetFormatStore();

      expect(store.read(), SheetFormat.excel);
      store.write(SheetFormat.both);
      expect(box.m['stock_sheet_last_format'], 'both');
      expect(store.read(), SheetFormat.both);
      store.write(SheetFormat.pdf);
      expect(store.read(), SheetFormat.pdf);
      box.m['stock_sheet_last_format'] = 'word';
      expect(store.read(), SheetFormat.excel);
    });
  });

  group('closing the screen mid-run', () {
    List<FileSystemEntity> written() => tmp.listSync();

    test('stops decoding, disposes the decoder and shares nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      })..gate = Completer<void>();
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = make(decoder, provider);
      final run = c.start(['a.jpg', 'b.jpg']);
      await pumpEventQueue();
      expect(decoder.calls, 1);

      c.onClose();
      decoder.gate!.complete();
      await run;
      await pumpEventQueue();

      expect(decoder.calls, 1);
      expect(decoder.disposed, isTrue);
      expect(provider.stockCalls, 0);
      expect(shared, isEmpty);
      expect(written(), isEmpty);
      expect(c.busy.value, isFalse);
    });

    test('during a thumbnail: the next photo is not decoded', () async {
      final thumbGate = Completer<void>();
      thumbOverride = (_) async {
        await thumbGate.future;
        return null;
      };
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = make(decoder, provider);
      final run = c.start(['a.jpg', 'b.jpg']);
      await pumpEventQueue();
      expect(decoder.calls, 1);

      c.onClose();
      thumbGate.complete();
      await run;
      await pumpEventQueue();

      expect(decoder.calls, 1);
      expect(decoder.disposed, isTrue);
      expect(provider.stockCalls, 0);
      expect(shared, isEmpty);
    });

    test('during the stock check: no share and no files', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final provider = _FakeProvider(stock: {_a: 1})
        ..stockGate = Completer<void>();
      final c = make(decoder, provider);
      final run = c.start(['a.jpg']);
      await pumpEventQueue();
      expect(provider.stockCalls, 1);

      c.onClose();
      provider.stockGate!.complete();
      await run;
      await pumpEventQueue();

      // The answer that came back after close is not written.
      expect(c.review.single.stage, ReadStage.checkingStock);
      expect(c.review.single.items, isEmpty);
      await c.makeSheet(SheetFormat.both);
      expect(shared, isEmpty);
      expect(pdfDocs, isEmpty);
      expect(written(), isEmpty);
      expect(c.files, isEmpty);
    });

    test('while writing: files already written are removed', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      pdfGate = Completer<void>();
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      await settled(c);
      final run = c.makeSheet(SheetFormat.both);
      for (var i = 0; i < 50 && written().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(written().map((f) => f.uri.pathSegments.last), [
        'Items-20261117-0905.xlsx',
      ]);

      c.onClose();
      pdfGate!.complete();
      await run;

      expect(shared, isEmpty);
      expect(written(), isEmpty);
      expect(c.files, isEmpty);
    });

    test('an out-of-stock choice after close builds nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);

      c.onClose();
      await c.chooseOutOfStock(OutOfStockChoice.includeRed);

      expect(shared, isEmpty);
      expect(written(), isEmpty);
    });

    test('Generate file after close writes nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      await settled(c);
      expect(c.phase.value, StockSheetPhase.reviewing);

      c.onClose();
      await c.makeSheet(SheetFormat.both);

      expect(shared, isEmpty);
      expect(pdfDocs, isEmpty);
      expect(written(), isEmpty);
    });
  });

  group('shared photo copies', () {
    late Directory outside;

    setUp(() async {
      outside = await Directory.systemTemp.createTemp('stock_sheet_gallery');
    });

    tearDown(() async {
      if (outside.existsSync()) await outside.delete(recursive: true);
    });

    File photo(Directory dir, String name) =>
        File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

    test('on close, photos in the temp folder go; others stay', () async {
      final cached = photo(tmp, 'shared_1.jpg');
      final nested = photo(
        Directory('${tmp.path}/sub')..createSync(),
        'shared_2.jpg',
      );
      final gallery = photo(outside, 'IMG_0001.jpg');
      // Inside the temp folder by text only: it resolves to the gallery photo.
      final sneaky =
          '${tmp.path}/../${outside.path.split('/').last}/IMG_0001.jpg';
      final c = make(_FakeDecoder({}), _FakeProvider());

      expect(
        c.offerShare([cached.path, nested.path, gallery.path, sneaky]),
        ShareOffer.started,
      );
      c.onClose();
      await untilGone([cached, nested]);

      expect(cached.existsSync(), isFalse);
      expect(nested.existsSync(), isFalse);
      expect(gallery.existsSync(), isTrue);
    });

    test('photos of a run and of an earlier share are all removed', () async {
      final first = photo(tmp, 'first.jpg');
      final second = photo(tmp, 'second.jpg');
      final decoder = _FakeDecoder({
        second.path: [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      c.offerShare([first.path]);
      await pumpEventQueue();
      c.offerShare([second.path]);
      await c.start([second.path]);
      await settled(c);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);

      c.onClose();
      await untilGone([first, second]);

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    test('a photo already gone does not stop the others', () async {
      final kept = photo(tmp, 'b.jpg');
      final c = make(_FakeDecoder({}), _FakeProvider());
      c.offerShare(['${tmp.path}/missing.jpg', kept.path]);
      await pumpEventQueue();
      c.onClose();
      await pumpEventQueue();
      expect(kept.existsSync(), isFalse);
    });
  });

  group('fixCode', () {
    const typed = '2001136';
    const noteItem = '1004765';
    const note = '99999995';

    /// a.jpg (A), b.jpg (B), bad.jpg (unreadable), c.jpg (A).
    Future<StockSheetController> fourPhotos(_FakeProvider provider) async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'bad.jpg': null,
        'c.jpg': [_ean(_a)],
      });
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg', 'bad.jpg', 'c.jpg']);
      await settled(c);
      expect(c.phase.value, StockSheetPhase.reviewing);
      return c;
    }

    test('a typed item code resolves the unresolved row in place', () async {
      final provider = _FakeProvider(
        stock: {typed: 3},
        known: const [_a, _b, typed],
      );
      final c = await fourPhotos(provider);
      expect(c.review[2].resolved, isFalse);

      final error = await c.fixCode(c.review[2].id, ' $typed ');

      expect(error, isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'bad.jpg', 'c.jpg']);
      final entry = c.review[2];
      expect(entry.typed, isTrue);
      expect(entry.notInErp, isEmpty);
      expect(entry.items.single.code.barcode, '20011369');
      expect(entry.items.single.code.itemCode, typed);
      expect(entry.items.single.included, isTrue);
      expect(entry.items.single.stock!.total, 3);
      expect(entry.items.single.stock!.racks.single.rack, _rack);
      expect(c.sheetPhotoCount, 4);
      expect(provider.itemRequests.last, [typed]);
      expect(provider.stockRequests.last, [typed]);
      expect(c.fixing.value, isFalse);
    });

    test('a Not in ERP row of a sheet photo is fixed on its own', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a), note],
      });
      final provider = _FakeProvider(
        stock: {_a: 1, noteItem: 2},
        known: const [_a, noteItem],
      );
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      expect(c.review, hasLength(2));
      expect(c.review[1].notInErp, [note]);
      final first = c.review[0];

      expect(await c.fixCode(c.review[1].id, noteItem), isNull);

      expect(c.review[0], same(first));
      expect(c.review[1].items.single.code.itemCode, noteItem);
      expect(c.review[1].notInErp, isEmpty);
      expect(c.review[1].typed, isTrue);
      expect(c.review[1].path, 'a.jpg');
      expect(c.sheetItemCount, 2);
      expect(c.photoCount, 1);
    });

    test('text that is not a code is refused without asking the ERP', () async {
      final provider = _FakeProvider();
      final c = await fourPhotos(provider);
      final calls = provider.itemRequests.length;

      final bad = c.review[2].id;
      expect(await c.fixCode(bad, 'ABC'), 'Not a barcode or item code');
      expect(await c.fixCode(bad, '12345678'), 'Not a barcode or item code');
      expect(provider.itemRequests, hasLength(calls));
      expect(c.review[2].resolved, isFalse);
    });

    test('a code the ERP does not know says Not in ERP', () async {
      final provider = _FakeProvider();
      final c = await fourPhotos(provider);

      expect(await c.fixCode(c.review[2].id, typed), 'Not in ERP');
      expect(c.review[2].resolved, isFalse);
      expect(c.review[2].typed, isFalse);
      expect(c.fixing.value, isFalse);
    });

    test('a code already on another row still resolves this one', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);

      expect(await c.fixCode(c.review[2].id, _ean(_a)), isNull);

      expect(c.review[0].items.single.code.itemCode, _a);
      expect(c.review[2].items.single.code.itemCode, _a);
      expect(c.review[2].typed, isTrue);
      expect(c.sheetPhotoCount, 4);
    });

    test('403 and network errors give the base messages', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);

      provider.itemsError = const StockAccessDenied();
      expect(
        await c.fixCode(c.review[2].id, _a),
        "You don't have access to stock levels.",
      );
      provider.stockError = Exception('offline');
      expect(
        await c.fixCode(c.review[2].id, _a),
        "Couldn't reach the ERP. Check the connection and try again.",
      );
      expect(c.review[2].resolved, isFalse);
      expect(c.fixing.value, isFalse);
    });

    test(
      'a row with an item, or still being read, is never overwritten',
      () async {
        final decoder = _FakeDecoder({
          'sheet': [_ean(_a), _ean(_b)],
          'bad': null,
        })..zoomGate = Completer<void>();
        final provider = _FakeProvider(
          stock: {_a: 1, _b: 1, typed: 3},
          known: const [_a, _b, typed],
        );
        final c = make(decoder, provider);
        await c.start(['sheet', 'bad']);
        await pumpEventQueue();
        expect(c.review.first.stage, ReadStage.zooming);
        final requests = provider.itemRequests.length;

        // Still being read: nothing to fix.
        expect(await c.fixCode(c.review[0].id, typed), isNull);
        expect(c.review.first.stage, ReadStage.zooming);
        expect(c.review.first.typed, isFalse);

        decoder.zoomGate!.complete();
        await settled(c);
        expect(reviewPaths(c), ['sheet', 'sheet', 'bad']);
        final before = c.review.toList();

        // The sheet's second row has an item: nothing to fix either.
        expect(await c.fixCode(c.review[1].id, typed), isNull);
        expect(c.review[1], same(before[1]));
        expect(c.review[1].typed, isFalse);
        expect(c.review[2].resolved, isFalse);
        // Refused without asking the ERP.
        expect(provider.itemRequests, hasLength(requests));
      },
    );

    test(
      'a code typed while a photo above becomes its rows lands on its own row',
      () async {
        final decoder = _FakeDecoder({
          'sheet': [_ean(_a), _ean(_b)],
          'bad': null, // "Unreadable photo": settled in round one
        })..zoomGate = Completer<void>();
        final provider = _FakeProvider(
          stock: {_a: 1, _b: 1, typed: 3},
          known: const [_a, _b, typed],
        );
        final c = make(decoder, provider);
        await c.start(['sheet', 'bad']);
        await pumpEventQueue();
        expect(c.review.map((e) => e.stage), [
          ReadStage.zooming,
          ReadStage.settled,
        ]);
        expect(c.review[1].decodeFailed, isTrue);
        // What the screen takes when "Type or scan code" is tapped on it.
        final tapped = c.review[1].id;

        // While the code is typed, the sheet photo above becomes its rows.
        decoder.zoomGate!.complete();
        await settled(c);
        expect(reviewPaths(c), ['sheet', 'sheet', 'bad']);
        final sheetRows = c.review.take(2).toList();

        expect(await c.fixCode(tapped, typed), isNull);

        expect(c.review[0], same(sheetRows[0]));
        expect(c.review[1], same(sheetRows[1]));
        expect(c.review[1].items.single.info.itemCode, _b);
        expect(c.review[1].typed, isFalse);
        expect(c.review[2].path, 'bad');
        expect(c.review[2].typed, isTrue);
        expect(c.review[2].items.single.info.itemCode, typed);
      },
    );

    test('closing during the lookup leaves the review alone', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);
      provider.itemsGate = Completer<void>();

      final fix = c.fixCode(c.review[2].id, _a);
      expect(c.fixing.value, isTrue);
      c.onClose();
      provider.itemsGate!.complete();
      await fix;

      expect(c.review[2].resolved, isFalse);
      expect(c.fixing.value, isFalse);
    });
  });

  group('addPhotos', () {
    test('more than the limit allows adds nothing and says why', () async {
      final decoder = _FakeDecoder({});
      final c = make(decoder, _FakeProvider());
      await c.start(List.generate(98, (i) => 'p$i.jpg'));
      await settled(c);
      expect(c.review, hasLength(98));
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['x.jpg', 'y.jpg', 'z.jpg']),
        'Only 2 more photos fit (limit 100).',
      );
      expect(c.review, hasLength(98));
      expect(decoder.calls, calls);
      expect(c.adding.value, isFalse);
    });

    test('one place left, then none, say so in the singular', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));
      await settled(c);

      expect(
        await c.addPhotos(['x.jpg', 'y.jpg']),
        'Only 1 more photo fits (limit 100).',
      );
      expect(await c.addPhotos(['x.jpg']), isNull);
      expect(c.review, hasLength(100));
      expect(await c.addPhotos(['y.jpg']), 'No more photos fit (limit 100).');
      expect(
        StockSheetController.roomMessage(3),
        'Only 3 more photos fit (limit 100).',
      );
    });

    test('photos already in the list are skipped', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'd.jpg': [_ean(_b)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
      await c.start(['a.jpg', 'b.jpg']);
      await settled(c);

      expect(await c.addPhotos(['b.jpg', 'd.jpg', 'd.jpg']), isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['a.jpg', 'd.jpg']),
        'Those photos are already in the list.',
      );
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
      expect(decoder.calls, calls);
    });

    test('a photo shared twice is read and listed once', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));

      await c.start(['a.jpg', 'b.jpg', 'a.jpg']);
      await settled(c);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(decoder.calls, 2);
    });

    test('new photos go after a reorder, checked by their own codes', () async {
      const c3 = '1000003';
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'bad.jpg': null,
        'd.jpg': [_ean(c3)],
        'e.jpg': ['not a code'],
      });
      final provider = _FakeProvider(
        stock: {_a: 1, _b: 1, c3: 2},
        known: const [_a, _b, c3],
      );
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg', 'bad.jpg']);
      await settled(c);
      c.reorder(0, 3);
      expect(reviewPaths(c), ['b.jpg', 'bad.jpg', 'a.jpg']);

      final added = c.addPhotos(['d.jpg', 'e.jpg']);
      expect(c.adding.value, isTrue);
      expect(await added, isNull);
      // Listed at once, not yet read.
      expect(c.adding.value, isFalse);
      expect(reviewPaths(c), ['b.jpg', 'bad.jpg', 'a.jpg', 'd.jpg', 'e.jpg']);
      expect(c.review.map((e) => e.number), [2, 3, 1, 4, 5]);
      await settled(c);

      expect(reviewPaths(c), ['b.jpg', 'bad.jpg', 'a.jpg', 'd.jpg', 'e.jpg']);
      expect(c.review[3].items.single.code.itemCode, c3);
      expect(c.review[3].items.single.stock!.total, 2);
      expect(c.review[4].resolved, isFalse);
      expect(c.review[4].rawValues, ['not a code']);
      expect(provider.itemRequests.last, [c3]);
      expect(provider.stockRequests.last, [c3]);
      expect(c.thumbnails.keys, containsAll(['d.jpg', 'e.jpg']));
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test(
      'three unchecked photos: one Retry check checks them all in one batch',
      () async {
        const c3 = '1000003';
        final decoder = _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'b.jpg': [_ean(_b)],
          'd.jpg': [_ean(c3)],
        });
        final provider = _FakeProvider(
          stock: {_a: 1, _b: 2, c3: 3},
          known: const [_a, _b, c3],
        )..stockError = Exception('offline');
        final c = make(decoder, provider);
        await c.start(['a.jpg', 'b.jpg', 'd.jpg']);
        await settled(c);
        expect(c.review.map((e) => e.unchecked), [true, true, true]);
        final items = provider.itemRequests.length;
        final stock = provider.stockRequests.length;

        expect(await c.retryCheck(), isNull);

        expect(provider.itemRequests, hasLength(items + 1));
        expect(provider.stockRequests, hasLength(stock + 1));
        expect(provider.itemRequests.last, unorderedEquals([_a, _b, c3]));
        expect(provider.stockRequests.last, unorderedEquals([_a, _b, c3]));
        expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
        expect(c.review.map((e) => e.unchecked), [false, false, false]);
        expect(c.review.map((e) => e.items.single.stock!.total), [1, 2, 3]);
        expect(c.review.map((e) => e.number), [1, 2, 3]);
        expect(c.rechecking.value, isFalse);
      },
    );

    test(
      'a failed Retry check leaves every unchecked photo unchecked',
      () async {
        final decoder = _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'b.jpg': [_ean(_b)],
          'd.jpg': [_ean(_a)],
        });
        final provider = _FakeProvider(stock: {_a: 1, _b: 2})
          ..stockError = Exception('offline');
        final c = make(decoder, provider);
        await c.start(['a.jpg', 'b.jpg', 'd.jpg']);
        await settled(c);
        expect(c.review.map((e) => e.unchecked), [true, true, true]);

        provider.stockError = Exception('still offline');
        expect(await c.retryCheck(), StockSheetController.offlineMessage);
        expect(c.review.map((e) => e.unchecked), [true, true, true]);
        expect(c.review.every((e) => e.items.isEmpty), isTrue);
        expect(c.rechecking.value, isFalse);
      },
    );

    test(
      'a failed check adds them unchecked; Retry check resolves both',
      () async {
        const c3 = '1000003';
        final decoder = _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'd.jpg': [_ean(_b)],
          'e.jpg': [_ean(c3)],
        });
        final provider = _FakeProvider(
          stock: {_a: 1, _b: 2, c3: 1},
          known: const [_a, _b, c3],
        );
        final c = make(decoder, provider);
        await c.start(['a.jpg']);
        await settled(c);
        provider.stockError = Exception('offline');

        expect(await c.addPhotos(['d.jpg', 'e.jpg']), isNull);
        await settled(c);

        expect(reviewPaths(c), ['a.jpg', 'd.jpg', 'e.jpg']);
        for (final entry in c.review.skip(1)) {
          expect(entry.unchecked, isTrue);
          expect(entry.items, isEmpty);
          expect(entry.included, isFalse);
        }
        // Never a false out-of-stock row.
        expect(c.sheetPhotoCount, 1);
        final decodes = decoder.calls;

        await c.retryCheck();

        expect(decoder.calls, decodes);
        expect(c.review[1].unchecked, isFalse);
        expect(c.review[1].items.single.code.itemCode, _b);
        expect(c.review[1].items.single.stock!.total, 2);
        expect(c.review[2].unchecked, isFalse);
        expect(c.review[2].items.single.code.itemCode, c3);
        expect(provider.stockRequests.last, [_b, c3]);
        expect(c.sheetPhotoCount, 3);
        expect(c.rechecking.value, isFalse);
      },
    );

    test('a failed Retry check leaves the photo unchecked', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      provider.stockError = Exception('offline');
      await c.addPhotos(['d.jpg']);
      await settled(c);
      provider.itemsError = Exception('still offline');

      expect(
        await c.retryCheck(),
        "Couldn't reach the ERP. Check the connection and try again.",
      );
      expect(c.review[1].unchecked, isTrue);
      expect(c.review[1].items, isEmpty);

      provider.itemsError = const StockAccessDenied();
      expect(await c.retryCheck(), "You don't have access to stock levels.");
      expect(c.review[1].unchecked, isTrue);
      expect(c.rechecking.value, isFalse);
    });

    test('a code typed during Retry check is not overwritten', () async {
      const typed = '2001136';
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(
        stock: {_a: 1, _b: 2, typed: 3},
        known: const [_a, _b, typed],
      );
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      provider.stockError = Exception('offline');
      await c.addPhotos(['d.jpg']);
      await settled(c);
      expect(c.review[1].unchecked, isTrue);
      final gate = provider.itemsGateOnce = Completer<void>();

      final retry = c.retryCheck();
      await pumpEventQueue();
      // The gate was taken by the retry's Item call.
      expect(provider.itemsGateOnce, isNull);
      expect(await c.fixCode(c.review[1].id, typed), isNull);
      expect(c.review[1].items.single.code.itemCode, typed);
      gate.complete();

      expect(await retry, isNull);
      expect(c.review[1].typed, isTrue);
      expect(c.review[1].unchecked, isFalse);
      expect(c.review[1].items.single.code.itemCode, typed);
    });

    test('closing mid-add appends nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      final gate = fingerprintGateOnce = Completer<void>();

      final added = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      expect(c.adding.value, isTrue);
      c.onClose();
      gate.complete();
      expect(await added, isNull);

      expect(reviewPaths(c), ['a.jpg']);
      expect(c.adding.value, isFalse);
      expect(decoder.decoded, ['a.jpg']);
    });

    test('closing while an added photo is checked writes nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      provider.stockGate = Completer<void>();

      expect(await c.addPhotos(['d.jpg']), isNull);
      await pumpEventQueue();
      expect(c.review.last.stage, ReadStage.checkingStock);
      c.onClose();
      provider.stockGate!.complete();
      await pumpEventQueue();

      expect(reviewPaths(c), ['a.jpg', 'd.jpg']);
      expect(c.review.last.items, isEmpty);
      expect(shared, isEmpty);
    });

    test('Generate file waits for an add in flight', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      await settled(c);
      provider.stockGate = Completer<void>();

      final added = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      await c.makeSheet(SheetFormat.excel);
      expect(shared, isEmpty);
      provider.stockGate!.complete();
      await added;
      await settled(c);

      expect(c.phase.value, StockSheetPhase.reviewing);
      await c.makeSheet(SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.done);
      expect(c.result.value!.rows.map((r) => r.photoPath), ['a.jpg', 'd.jpg']);
    });
  });

  group('a photo of several items', () {
    const c3 = '1000003';

    Future<StockSheetController> sheetAndOne([_FakeProvider? provider]) async {
      final c = make(
        _FakeDecoder({
          'sheet.jpg': [_ean(c3), _ean(_a), _ean(_b)],
          'one.jpg': [_ean(_a)],
        }),
        provider ?? _FakeProvider(stock: {_a: 1, _b: 1, c3: 1},
            known: const [_a, _b, c3]),
      );
      fingerprints.addAll({'sheet.jpg': 'S', 'one.jpg': 'O'});
      await c.start(['sheet.jpg', 'one.jpg']);
      await settled(c);
      return c;
    }

    test('gives one row per item, in the order read', () async {
      final c = await sheetAndOne();
      expect(reviewPaths(c), ['sheet.jpg', 'sheet.jpg', 'sheet.jpg', 'one.jpg']);
      expect(
        c.review.map((e) => e.items.single.code.itemCode),
        [c3, _a, _b, _a],
      );
      expect(c.review.map((e) => e.id).toSet(), hasLength(4));
      expect(c.photoCount, 2);
      expect(c.sheetItemCount, 4);
      expect(c.sheetPhotoCount, 2);
      // The limit counts photos, not rows.
      expect(c.photoRoom, StockSheetController.maxPhotos - 2);
    });

    test('a row switches off on its own', () async {
      final c = await sheetAndOne();
      c.setIncluded(1, false);
      expect(c.review.map((e) => e.included), [true, false, true, true]);
      expect(c.sheetItemCount, 3);
      expect(c.sheetPhotoCount, 2);
    });

    test('the file has a row per item and counts the photo once', () async {
      final c = await sheetAndOne();
      await c.makeSheet(SheetFormat.pdf);
      final doc = pdfDocs.single;
      expect(doc.rows.map((r) => r.barcode), [
        _ean(c3),
        _ean(_a),
        _ean(_b),
        _ean(_a),
      ]);
      expect(doc.rows.map((r) => r.photoIndex), [0, 0, 0, 1]);
      expect(doc.subtitle, '17/11/2026 09:05 · 2 photos · 4 items · 0 out of stock');
    });

    test('Undo puts back one row although the photo has others', () async {
      final c = await sheetAndOne();
      final removed = c.removeAt(1)!;
      expect(c.review, hasLength(3));
      expect(c.photoCount, 2);

      c.restore(removed, 1);

      expect(c.review, hasLength(4));
      expect(c.review[1].items.single.code.itemCode, _a);
      expect(c.review[1].path, 'sheet.jpg');
      // Restoring twice adds nothing.
      c.restore(removed, 1);
      expect(c.review, hasLength(4));
    });

    test('removing every row of a photo frees its place', () async {
      final c = await sheetAndOne();
      for (var i = 0; i < 3; i++) {
        c.removeAt(0);
      }
      expect(c.photoCount, 1);
      expect(c.photoRoom, StockSheetController.maxPhotos - 1);
    });

    test('Retry check turns an unchecked photo into its rows', () async {
      final provider = _FakeProvider(
        stock: {_a: 1, _b: 2, c3: 3},
        known: const [_a, _b, c3],
      );
      final c = make(
        _FakeDecoder({
          'one.jpg': [_ean(_a)],
          'sheet.jpg': [_ean(_b), _ean(c3)],
        }),
        provider,
      );
      await c.start(['one.jpg']);
      await settled(c);
      provider.stockError = Exception('offline');
      expect(await c.addPhotos(['sheet.jpg']), isNull);
      await settled(c);
      expect(c.review, hasLength(2));
      expect(c.review[1].unchecked, isTrue);

      expect(await c.retryCheck(), isNull);

      expect(reviewPaths(c), ['one.jpg', 'sheet.jpg', 'sheet.jpg']);
      expect(c.review.skip(1).map((e) => e.items.single.code.itemCode), [
        _b,
        c3,
      ]);
      expect(c.review.every((e) => !e.unchecked), isTrue);
    });
  });

  group('ERP images', () {
    test('each Item image is fetched once and keys its rows', () async {
      final fetched = <String>[];
      final thumb = Uint8List.fromList([9, 9]);
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'b.jpg': [_ean(_b)],
          'c.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1, _b: 1}, images: {_a: '/files/a.jpg'}),
        itemThumbnail: (url) async {
          fetched.add(url);
          return thumb;
        },
      );
      await c.start(['a.jpg', 'b.jpg', 'c.jpg']);
      await settled(c);

      expect(fetched, ['/files/a.jpg']);
      expect(c.thumbnails[ItemInfo.thumbnailKey(_a)], thumb);
      expect(c.thumbnails.containsKey(ItemInfo.thumbnailKey(_b)), isFalse);

      await c.makeSheet(SheetFormat.pdf);
      final doc = pdfDocs.single;
      expect(doc.rows.map((r) => r.imageKey), [
        ItemInfo.thumbnailKey(_a),
        null,
        ItemInfo.thumbnailKey(_a),
      ]);
      expect(doc.thumbnails[ItemInfo.thumbnailKey(_a)], thumb);
    });

    test(
      'a second run asks for the Item and stock afresh, its image in hand',
      () async {
        final fetched = <String>[];
        final thumb = Uint8List.fromList([9, 9]);
        final provider = _FakeProvider(
          stock: {_a: 1},
          images: {_a: '/files/a.jpg'},
        );
        final c = make(
          _FakeDecoder({
            'a.jpg': [_ean(_a)],
          }),
          provider,
          itemThumbnail: (url) async {
            fetched.add(url);
            return thumb;
          },
        );
        await c.start(['a.jpg']);
        await settled(c);
        expect(c.thumbnails[ItemInfo.thumbnailKey(_a)], thumb);
        expect(c.review.single.items.single.stock!.total, 1);

        // Sold out between the two runs.
        provider.stock.remove(_a);
        await c.start(['a.jpg']);
        await settled(c);

        expect(c.review.single.items.single.info.itemCode, _a);
        // The second run's answer, not the first's.
        expect(c.review.single.items.single.stock?.total ?? 0, 0);
        // The image came with the rows, before they settled.
        expect(c.thumbnails[ItemInfo.thumbnailKey(_a)], thumb);
        expect(fetched, ['/files/a.jpg', '/files/a.jpg']);
        expect(provider.itemRequests, [
          [_a],
          [_a],
        ]);
        expect(provider.stockRequests, [
          [_a],
          [_a],
        ]);
      },
    );

    test(
      'a late answer from the last review fills nothing in the new one',
      () async {
        final provider = _FakeProvider(stock: {_a: 1, _b: 1})
          ..stockGate = Completer<void>();
        final c = make(
          _FakeDecoder({
            'p1': [_ean(_a)],
            'p2': [_ean(_b)],
            'q1': [_ean(_a)],
            'q2': [_ean(_b)],
          }),
          provider,
        );
        await c.start(['p1', 'p2']);
        await pumpEventQueue();
        expect(provider.stockRequests, [
          [_a, _b],
        ]);

        await c.start(['q1']);
        await pumpEventQueue();
        // The new review asks for itself, though the old batch is in flight.
        expect(provider.stockRequests, [
          [_a, _b],
          [_a],
        ]);
        provider.stockGate!.complete();
        await settled(c);
        expect(c.review.single.items.single.info.itemCode, _a);
        expect(c.phase.value, StockSheetPhase.reviewing);

        // _b was only in the old review's answer: it is asked for again.
        provider.stockGate = null;
        expect(await c.addPhotos(['q2']), isNull);
        await settled(c);
        expect(provider.itemRequests.last, [_b]);
        expect(provider.stockRequests.last, [_b]);
        expect(c.review.last.items.single.info.itemCode, _b);
      },
    );

    test('an image that fails leaves the cell blank, not the run', () async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1}, images: {_a: '/files/a.jpg'}),
        itemThumbnail: (url) async => throw Exception('404'),
      );
      await c.start(['a.jpg']);
      await settled(c);

      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.thumbnails.containsKey(ItemInfo.thumbnailKey(_a)), isFalse);
    });

    test('a typed code brings its Item image', () async {
      final fetched = <String>[];
      final c = make(
        _FakeDecoder({'bad.jpg': null}),
        _FakeProvider(stock: {_b: 1}, images: {_b: '/files/b.jpg'}),
        itemThumbnail: (url) async {
          fetched.add(url);
          return Uint8List.fromList([1]);
        },
      );
      await c.start(['bad.jpg']);
      await settled(c);
      expect(fetched, isEmpty);

      expect(await c.fixCode(c.review[0].id, _b), isNull);

      expect(fetched, ['/files/b.jpg']);
      expect(c.thumbnails.containsKey(ItemInfo.thumbnailKey(_b)), isTrue);
    });
  });

  group('removeAt and restore', () {
    Future<StockSheetController> three() async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'b.jpg': [_ean(_b)],
          'd.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1, _b: 1}),
      );
      fingerprints.addAll({'a.jpg': 'A', 'b.jpg': 'B', 'd.jpg': 'D'});
      await c.start(['a.jpg', 'b.jpg', 'd.jpg']);
      await settled(c);
      return c;
    }

    test('removeAt drops the entry and returns it', () async {
      final c = await three();

      final removed = c.removeAt(1);

      expect(removed?.path, 'b.jpg');
      expect(reviewPaths(c), ['a.jpg', 'd.jpg']);
      expect(c.removeAt(5), isNull);
      expect(c.removeAt(-1), isNull);
    });

    test('removeAt works while photos are added, not while fixing', () async {
      final c = await three();
      c.adding.value = true;

      expect(c.canRemove, isTrue);
      expect(c.removeAt(0)?.path, 'a.jpg');
      expect(reviewPaths(c), ['b.jpg', 'd.jpg']);

      c.adding.value = false;
      for (final flag in [c.rechecking, c.fixing, c.busy]) {
        flag.value = true;
        expect(c.canRemove, isFalse);
        expect(c.removeAt(0), isNull);
        flag.value = false;
      }
      expect(c.canRemove, isTrue);
    });

    test('restore puts the entry back at its index', () async {
      final c = await three();
      final removed = c.removeAt(1)!;

      c.restore(removed, 1);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
    });

    test('restore clamps the index after the list shrank', () async {
      final c = await three();
      final removed = c.removeAt(2)!;
      c.removeAt(1);

      c.restore(removed, 2);

      expect(reviewPaths(c), ['a.jpg', 'd.jpg']);
    });

    test('restore ignores an entry that is already listed', () async {
      final c = await three();
      final removed = c.removeAt(0)!;
      c.restore(removed, 0);
      c.restore(removed, 0);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
    });

    test(
      'restore skips a photo that was added again under a new path',
      () async {
        final c = await three();
        fingerprints['a2.jpg'] = 'A';
        final removed = c.removeAt(0)!;
        expect(await c.addPhotos(['a2.jpg']), isNull);

        c.restore(removed, 0);

        expect(reviewPaths(c), ['b.jpg', 'd.jpg', 'a2.jpg']);
      },
    );

    test('a removed photo can be added again', () async {
      final c = await three();
      fingerprints['a2.jpg'] = 'A';
      c.removeAt(0);

      expect(await c.addPhotos(['a2.jpg']), isNull);
      expect(reviewPaths(c), contains('a2.jpg'));
    });
  });

  group('picker copies', () {
    test('onClose clears the file picker temporary files', () async {
      var cleared = 0;
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(stock: {}),
        clearPickerFiles: () async => cleared++,
      );
      c.onClose();
      await pumpEventQueue();
      expect(cleared, 1);
    });

    test('onClose ignores an error from the clean-up', () async {
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(stock: {}),
        clearPickerFiles: () async => throw StateError('no picker'),
      );
      c.onClose();
      await pumpEventQueue();
    });
  });

  group('duplicates by content', () {
    test('start reads two copies of the same photo once', () async {
      fingerprints.addAll({'a.jpg': 'X', 'b.jpg': 'X'});
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));

      await c.start(['a.jpg', 'b.jpg']);
      await settled(c);

      expect(decoder.decoded, ['a.jpg']);
      expect(c.review.map((e) => e.path), ['a.jpg']);
    });

    test('addPhotos skips a photo already listed by content', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'c.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      await settled(c);
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['c.jpg']),
        StockSheetController.alreadyListedMessage,
      );
      expect(decoder.calls, calls);
      expect(c.review.length, 1);
    });
  });

  group('offerShare', () {
    Future<StockSheetController> reviewing() async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'n1.jpg': [_ean(_b)],
        'n2.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
      await c.start(['a.jpg', 'b.jpg']);
      await settled(c);
      expect(c.phase.value, StockSheetPhase.reviewing);
      return c;
    }

    test('from idle it starts the share', () {
      final c = make(_FakeDecoder({}), _FakeProvider());
      expect(c.offerShare(['a.jpg']), ShareOffer.started);
      expect(c.sharedPaths, ['a.jpg']);
      expect(c.shareSerial.value, 1);
      expect(c.pendingShare, isEmpty);
    });

    test('while busy it is refused and nothing changes', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      })..gate = Completer<void>();
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      final run = c.start(['a.jpg']);

      expect(c.offerShare(['b.jpg']), ShareOffer.refusedBusy);
      expect(c.pendingShare, isEmpty);
      expect(c.shareSerial.value, 0);
      decoder.gate!.complete();
      await run;
    });

    test('while reviewing it is held, with the review untouched', () async {
      final c = await reviewing();
      c.setIncluded(1, false);

      expect(c.offerShare(['n1.jpg', 'n2.jpg']), ShareOffer.pending);
      await pumpEventQueue();

      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShareFits, isTrue);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(c.review[1].included, isFalse);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.shareSerial.value, 0);
    });

    test('while the out-of-stock question is open it is held', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);

      expect(c.offerShare(['n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg']);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);
    });

    test('pendingShareFits follows the 100-photo limit', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));
      await settled(c);
      c.offerShare(['x.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isTrue);
      c.offerShare(['x.jpg', 'y.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isFalse);
    });

    test('a held share counts only new photos', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final c = await reviewing();

      c.offerShare(['c.jpg', 'd.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, ['d.jpg']);
    });

    test('a held share of only duplicates is not asked', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final c = await reviewing();

      c.offerShare(['c.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, isEmpty);
      expect(c.alreadyListed.value, 1);
    });

    test('Add appends the held photos', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      expect(await c.resolvePendingShare(PendingShareChoice.add), isNull);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('Add from the out-of-stock question returns to the review', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'n1.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      c.offerShare(['n1.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.add);

      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.result.value, isNull);
      expect(reviewPaths(c), ['a.jpg', 'n1.jpg']);
    });

    test('Add that will not fit adds nothing and is held again', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));
      await settled(c);
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      expect(await c.resolvePendingShare(PendingShareChoice.add), isNull);
      expect(c.review, hasLength(99));
      // The screen asks again, offering only Start again.
      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShareFits, isFalse);
    });

    test('a share of photos already in the list says so, not asks', () async {
      final c = await reviewing();
      c.offerShare(['b.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, isEmpty);
      expect(c.alreadyListed.value, 1);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
    });

    test('Start again replaces the review with the held photos', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.startAgain);

      expect(reviewPaths(c), ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.sharedPaths, ['n1.jpg', 'n2.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('Cancel drops the held photos and keeps the review', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.cancel);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });
  });

  test('added and held photos in the temp folder go on close', () async {
    final first = File('${tmp.path}/first.jpg')..writeAsBytesSync([1]);
    final added = File('${tmp.path}/added.jpg')..writeAsBytesSync([1]);
    final held = File('${tmp.path}/held.jpg')..writeAsBytesSync([1]);
    final decoder = _FakeDecoder({
      first.path: [_ean(_a)],
      added.path: [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start([first.path]);
    await settled(c);
    await c.addPhotos([added.path]);
    expect(c.offerShare([held.path]), ShareOffer.pending);
    await c.resolvePendingShare(PendingShareChoice.cancel);
    expect(added.existsSync(), isTrue);

    c.onClose();
    await untilGone([first, added, held]);

    expect(first.existsSync(), isFalse);
    expect(added.existsSync(), isFalse);
    expect(held.existsSync(), isFalse);
  });

  test('refused and held photos in the temp folder go on close', () async {
    File photo(String name) => File('${tmp.path}/$name')..writeAsBytesSync([1]);
    final refused = photo('refused.jpg');
    final full1 = photo('full1.jpg');
    final full2 = photo('full2.jpg');
    final held = photo('held.jpg');
    final decoder = _FakeDecoder({})..gate = Completer<void>();
    final c = make(decoder, _FakeProvider());
    final run = c.start(List.generate(99, (i) => 'p$i.jpg'));
    expect(c.offerShare([refused.path]), ShareOffer.refusedBusy);
    decoder.gate!.complete();
    await run;
    expect(
      await c.addPhotos([full1.path, full2.path]),
      'Only 1 more photo fits (limit 100).',
    );
    expect(c.offerShare([held.path]), ShareOffer.pending);

    c.onClose();
    await untilGone([refused, full1, full2, held]);

    expect(refused.existsSync(), isFalse);
    expect(full1.existsSync(), isFalse);
    expect(full2.existsSync(), isFalse);
    expect(held.existsSync(), isFalse);
  });

  group('clean-up in extra intake folders', () {
    late Directory group;
    late Directory elsewhere;
    setUp(() {
      group = Directory('${tmp.path}_group')..createSync();
      elsewhere = Directory('${tmp.path}_elsewhere')..createSync();
    });
    tearDown(() {
      for (final d in [group, elsewhere]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });

    test(
      'onClose deletes given photos in an extra intake folder but not elsewhere',
      () async {
        final x = File('${group.path}/x.jpg')..writeAsBytesSync([1]);
        final y = File('${elsewhere.path}/y.jpg')..writeAsBytesSync([1]);
        final c = make(
          _FakeDecoder({}),
          _FakeProvider(),
          extraRoots: () async => [group.path],
        );
        await c.start([x.path, y.path]);
        await settled(c);

        c.onClose();
        await untilGone([x]);

        expect(x.existsSync(), isFalse);
        expect(y.existsSync(), isTrue);
      },
    );

    test('copies in sub-folders of the native temporary folder are deleted, '
        'the folders kept', () async {
      // sharedFolders returns NSTemporaryDirectory() itself: "Choose files…"
      // copies land in its <bundle id>-Inbox/, drops in its dropped/.
      final inbox = Directory('${group.path}/com.ddmco.multimax-Inbox')
        ..createSync();
      final dropped = Directory('${group.path}/dropped')..createSync();
      final picked = File('${inbox.path}/picked.jpg')..writeAsBytesSync([1]);
      final drop = File('${dropped.path}/drop.png')..writeAsBytesSync([1]);
      final kept = File('${inbox.path}/not-given.jpg')..writeAsBytesSync([1]);
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(),
        extraRoots: () async => [group.path],
      );
      await c.start([picked.path, drop.path]);
      await settled(c);

      c.onClose();
      await untilGone([picked, drop]);

      expect(picked.existsSync(), isFalse);
      expect(drop.existsSync(), isFalse);
      expect(kept.existsSync(), isTrue, reason: 'only given paths go');
      expect(inbox.existsSync(), isTrue);
      expect(dropped.existsSync(), isTrue);
    });

    test('empty, relative and root folders are not clean-up roots', () async {
      final y = File('${elsewhere.path}/y.jpg')..writeAsBytesSync([1]);
      final t = File('${tmp.path}/t.jpg')..writeAsBytesSync([1]);
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(),
        extraRoots: () async => ['', '/', 'relative'],
      );
      await c.start([y.path, t.path]);
      await settled(c);

      c.onClose();
      await untilGone([t]);

      expect(t.existsSync(), isFalse);
      expect(y.existsSync(), isTrue);
    });

    test(
      'a failing extra-folder lookup still cleans the temp folder',
      () async {
        final t = File('${tmp.path}/t.jpg')..writeAsBytesSync([1]);
        final c = make(
          _FakeDecoder({}),
          _FakeProvider(),
          extraRoots: () async => throw Exception('no channel'),
        );
        await c.start([t.path]);
        await settled(c);

        c.onClose();
        await untilGone([t]);

        expect(t.existsSync(), isFalse);
      },
    );
  });

  group('a share during an add', () {
    /// a.jpg and b.jpg in the review, d.jpg being added: its fingerprinting
    /// waits for the gate returned.
    Future<(StockSheetController, Future<String?>, Completer<void>)> addingOne(
      _FakeProvider provider,
    ) async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'd.jpg': [_ean(_b)],
        'n1.jpg': [_ean(_a)],
        'n2.jpg': [_ean(_b)],
      });
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg']);
      await settled(c);
      final gate = fingerprintGateOnce = Completer<void>();
      final add = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      expect(c.adding.value, isTrue);
      return (c, add, gate);
    }

    test('it is held, not refused', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add, gate) = await addingOne(provider);

      expect(c.offerShare(['n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg']);
      expect(c.pendingShareFits, isTrue);

      gate.complete();
      await add;
    });

    test('Add waits for the add, then appends both in order', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add, gate) = await addingOne(provider);
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      final resolved = c.resolvePendingShare(PendingShareChoice.add);
      await pumpEventQueue();
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      gate.complete();

      expect(await add, isNull);
      expect(await resolved, isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg', 'n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.adding.value, isFalse);
    });

    test('Start again appends nothing from the add in flight', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add, gate) = await addingOne(provider);
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      final resolved = c.resolvePendingShare(PendingShareChoice.startAgain);
      await pumpEventQueue();
      gate.complete();
      await add;
      expect(await resolved, isNull);

      expect(reviewPaths(c), ['n1.jpg', 'n2.jpg']);
      expect(c.sharedPaths, ['n1.jpg', 'n2.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('the photos being added count against the limit', () async {
      final decoder = _FakeDecoder({});
      final c = make(decoder, _FakeProvider());
      await c.start(List.generate(97, (i) => 'p$i.jpg'));
      await settled(c);
      final gate = fingerprintGateOnce = Completer<void>();
      final add = c.addPhotos(['x1.jpg', 'x2.jpg']);
      expect(c.photoRoom, 1);

      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isFalse);
      // A photo already being added is not counted twice.
      c.pendingShare.assignAll(['x1.jpg', 'n1.jpg']);
      expect(c.pendingShareFits, isTrue);

      gate.complete();
      await add;
      expect(c.photoRoom, 1);
    });

    test(
      'an Add that no longer fits once the adds land is held again',
      () async {
        final decoder = _FakeDecoder({});
        final c = make(decoder, _FakeProvider());
        await c.start(List.generate(96, (i) => 'p$i.jpg'));
        await settled(c);
        final gate = fingerprintGateOnce = Completer<void>();
        final add = c.addPhotos(['x1.jpg', 'x2.jpg']);

        // Each fits beside the review and the add, but not both.
        c.offerShare(['n1.jpg', 'n2.jpg']);
        await pumpEventQueue();
        expect(c.pendingShareFits, isTrue);
        final first = c.resolvePendingShare(PendingShareChoice.add);
        c.offerShare(['m1.jpg', 'm2.jpg']);
        await pumpEventQueue();
        expect(c.pendingShareFits, isTrue);
        final second = c.resolvePendingShare(PendingShareChoice.add);
        gate.complete();

        await add;
        expect(await first, isNull);
        expect(await second, isNull);
        expect(c.review, hasLength(100));
        expect(reviewPaths(c).skip(96), [
          'x1.jpg',
          'x2.jpg',
          'n1.jpg',
          'n2.jpg',
        ]);
        expect(c.pendingShare, ['m1.jpg', 'm2.jpg']);
        expect(c.pendingShareFits, isFalse);
      },
    );

    test('a second share joins the one waiting, each photo once', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add, gate) = await addingOne(provider);

      c.offerShare(['n1.jpg']);

      await pumpEventQueue();
      expect(c.offerShare(['n2.jpg', 'n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);

      gate.complete();
      await add;
    });
  });

  group('the card', () {
    final eanA = _ean(_a);

    test(
      'the first opening of an in-stock card fetches its Stock Ageing once',
      () async {
        final provider = _FakeProvider(stock: {_a: 384})
          ..ageing[_a] = [_ageingA];
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
          }),
          provider,
        );
        await c.start(['p1']);
        await settled(c);
        final id = c.review.single.id;
        c.toggleCard(id);
        expect(c.openCards, {id});
        expect(c.ageing[_a]!.status, AgeingStatus.loading);
        await pumpEventQueue();
        expect(c.ageing[_a]!.status, AgeingStatus.ready);
        expect(c.ageing[_a]!.rows, [_ageingA]);
        c.toggleCard(id);
        expect(c.openCards, isEmpty);
        c.toggleCard(id);
        await pumpEventQueue();
        expect(provider.ageingRequests, [_a]);
      },
    );

    test('an out-of-stock card opens without a fetch', () async {
      final provider = _FakeProvider(); // no stock: out of stock
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
        }),
        provider,
      );
      await c.start(['p1']);
      await settled(c);
      c.toggleCard(c.review.single.id);
      await pumpEventQueue();
      expect(c.openCards, {c.review.single.id});
      expect(c.ageing, isEmpty);
      expect(provider.ageingRequests, isEmpty);
    });

    test(
      'no row, a failure and no access each have their state; Retry asks again',
      () async {
        final provider = _FakeProvider(stock: {_a: 5});
        final c = make(
          _FakeDecoder({
            'p1': [eanA],
          }),
          provider,
        );
        await c.start(['p1']);
        await settled(c);
        c.toggleCard(c.review.single.id);
        await pumpEventQueue();
        expect(c.ageing[_a]!.status, AgeingStatus.missing);
        provider.ageingError = Exception('offline');
        await c.retryAgeing(_a);
        expect(c.ageing[_a]!.status, AgeingStatus.failed);
        provider.ageingError = const StockAccessDenied();
        await c.retryAgeing(_a);
        expect(c.ageing[_a]!.status, AgeingStatus.denied);
        expect(provider.ageingRequests, [_a, _a, _a]);
      },
    );

    test('Retry shows the fetch in flight and is not run twice', () async {
      final provider = _FakeProvider(stock: {_a: 5})
        ..ageingError = Exception('offline');
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
        }),
        provider,
      );
      await c.start(['p1']);
      await settled(c);
      c.toggleCard(c.review.single.id);
      await pumpEventQueue();
      expect(c.ageing[_a]!.status, AgeingStatus.failed);

      provider
        ..ageingError = null
        ..ageing[_a] = [_ageingA]
        ..ageingGate = Completer<void>();
      final retry = c.retryAgeing(_a);
      expect(c.ageing[_a]!.status, AgeingStatus.loading);
      await c.retryAgeing(_a); // in flight: ignored
      provider.ageingGate!.complete();
      await retry;
      expect(c.ageing[_a]!.status, AgeingStatus.ready);
      expect(provider.ageingRequests, [_a, _a]);
    });

    test('a card that is not ready does not open', () async {
      final decoder = _FakeDecoder({
        'p1': [eanA],
      })..gate = Completer<void>();
      final c = make(decoder, _FakeProvider());
      unawaited(c.start(['p1']));
      await pumpEventQueue();
      c.toggleCard(c.review.single.id);
      expect(c.openCards, isEmpty);
      decoder.gate!.complete();
    });

    test('two rows of one item share one fetch and one state', () async {
      final provider = _FakeProvider(stock: {_a: 384})..ageing[_a] = [_ageingA];
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
          'p2': [eanA],
        }),
        provider,
      );
      await c.start(['p1', 'p2']);
      await settled(c);
      expect(c.review, hasLength(2));
      c.toggleCard(c.review[0].id);
      c.toggleCard(c.review[1].id);
      await pumpEventQueue();
      expect(c.openCards, {c.review[0].id, c.review[1].id});
      expect(provider.ageingRequests, [_a]);
      expect(c.ageing.keys, [_a]);
    });

    test('an answer after the review was cleared is dropped', () async {
      final provider = _FakeProvider(stock: {_a: 384})
        ..ageing[_a] = [_ageingA]
        ..ageingGate = Completer<void>();
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
          'p2': [eanA],
        }),
        provider,
      );
      await c.start(['p1']);
      await settled(c);
      c.toggleCard(c.review.single.id);
      expect(c.ageing, isNotEmpty);

      await c.start(['p2']);
      expect(c.openCards, isEmpty);
      expect(c.ageing, isEmpty);
      provider.ageingGate!.complete();
      await pumpEventQueue();
      expect(c.ageing, isEmpty);
    });

    test('a removed row with an open card comes back open', () async {
      final provider = _FakeProvider(stock: {_a: 384})..ageing[_a] = [_ageingA];
      final c = make(
        _FakeDecoder({
          'p1': [eanA],
        }),
        provider,
      );
      await c.start(['p1']);
      await settled(c);
      final id = c.review.single.id;
      c.toggleCard(id);
      final removed = c.removeAt(0)!;
      c.restore(removed, 0);
      expect(c.openCards, {id});
    });
  });
}
