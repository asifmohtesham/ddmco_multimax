import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';
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

class _FakeDecoder implements PhotoDecoder {
  _FakeDecoder(this.codes, {this.unsupported = false});
  final Map<String, List<String>?> codes;
  final bool unsupported;
  final Set<String> throwFor = {};
  int calls = 0;
  bool disposed = false;

  /// When set, every decode waits for it.
  Completer<void>? gate;

  @override
  Future<List<String>?> decode(String path) async {
    calls++;
    await gate?.future;
    if (unsupported) throw UnsupportedError('no');
    if (throwFor.contains(path)) throw Exception('boom');
    return codes[path];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeProvider extends StockSheetProvider {
  _FakeProvider({this.stock = const {}});
  final Map<String, double> stock;
  final List<String> known = const [_a, _b];
  Object? stockError;
  int stockCalls = 0;

  /// When set, the stock call waits for it.
  Completer<void>? stockGate;

  @override
  Future<Map<String, ItemInfo>> fetchItems(List<String> codes) async => {
    for (final c in codes.where(known.contains))
      c: ItemInfo(itemCode: c, itemName: 'Item $c'),
  };

  @override
  Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(
    List<String> codes,
  ) async {
    stockCalls++;
    await stockGate?.future;
    final error = stockError;
    if (error != null) {
      stockError = null;
      throw error;
    }
    return [
      for (final c in codes) {'item_code': c, 'bal_qty': stock[c] ?? 0},
    ];
  }
}

void main() {
  late Directory tmp;
  late List<List<XFile>> shared;
  late List<StockSheetDocument> pdfDocs;

  Future<Uint8List?> Function(String)? thumbOverride;

  /// When set, the PDF writer waits for it.
  Completer<void>? pdfGate;

  /// When set, the next share throws it.
  Object? shareError;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stock_sheet_ctrl');
    shared = [];
    pdfDocs = [];
    thumbOverride = null;
    pdfGate = null;
    shareError = null;
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  StockSheetController make(_FakeDecoder decoder, _FakeProvider provider) =>
      StockSheetController(
        decoderFactory: () => decoder,
        provider: provider,
        shareFiles: (f) async {
          final error = shareError;
          if (error != null) {
            shareError = null;
            throw error;
          }
          shared.add(f);
        },
        now: () => DateTime(2026, 11, 17, 9, 5),
        tempDir: () async => tmp,
        writePdf: (doc) async {
          await pdfGate?.future;
          pdfDocs.add(doc);
          return Uint8List.fromList([1, 2, 3]);
        },
        makeThumbnail:
            thumbOverride ??
            (p) async => Uint8List.fromList(
              img.encodeJpg(img.Image(width: 4, height: 4)),
            ),
      );

  test('more than 100 photos is refused and nothing is decoded', () async {
    final decoder = _FakeDecoder({});
    final c = make(decoder, _FakeProvider());
    await c.start(List.generate(101, (i) => 'p$i.jpg'), SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      'Share up to 100 photos at a time (you shared 101).',
    );
    expect(decoder.calls, 0);
  });

  test('all in stock builds at once: one xlsx, or two for both', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 5});
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(
      shared.single.single.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(File(shared.single.single.path).existsSync(), isTrue);
    expect(c.decoded.value, 1);
    expect(c.busy.value, isFalse);

    await c.start(['a.jpg'], SheetFormat.both);
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

  test('out of stock asks; dismissing cancels without sharing', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    expect(c.result.value!.outOfStockCount, 1);
    await c.chooseOutOfStock(null);
    expect(c.phase.value, StockSheetPhase.idle);
    expect(shared, isEmpty);
  });

  test('leaveOut drops red rows and hides the status column', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 3}));
    await c.start(['a.jpg', 'b.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.every((r) => !r.outOfStock), isTrue);
    expect(pdfDocs.single.rows, hasLength(1));
    expect(pdfDocs.single.showStatus, isFalse);
    // The out-of-stock row is not in the file, so the count is not shown.
    expect(pdfDocs.single.subtitle, '17/11/2026 09:05 · 2 photos · 1 item');
  });

  test('plural counts in the subtitle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a), _ean(_b)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['a.jpg', 'b.jpg'], SheetFormat.pdf);
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
    await c.start(['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includeRed);
    expect(pdfDocs.single.highlightOutOfStock, isTrue);
    expect(pdfDocs.single.showStatus, isTrue);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 1 out of stock',
    );
    await c.start(['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includePlain);
    expect(pdfDocs.last.highlightOutOfStock, isFalse);
    expect(pdfDocs.last.showStatus, isTrue);
  });

  test('retry after a stock failure does not decode again', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 2})..stockError = Exception('x');
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Couldn't reach the ERP. Check the connection and try again.",
    );
    expect(decoder.calls, 1);
    await c.retry();
    expect(decoder.calls, 1);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared, hasLength(1));
  });

  test('an unreadable photo is listed and the run completes', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['bad.jpg', 'a.jpg'], SheetFormat.excel);
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
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(c.errorMessage.value, "You don't have access to stock levels.");
    expect(c.result.value, isNull);
  });

  test('UnsupportedError from the decoder gives the device message', () async {
    final decoder = _FakeDecoder({}, unsupported: true);
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Reading barcodes from photos isn't supported on this device.",
    );
    expect(decoder.disposed, isTrue);
  });

  test('start while busy is a no-op; reset clears when idle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    final first = c.start(['a.jpg'], SheetFormat.excel);
    expect(c.busy.value, isTrue);
    await c.start(['a.jpg'], SheetFormat.excel);
    await first;
    expect(decoder.calls, 1);
    expect(shared, hasLength(1));

    c.reset();
    expect(c.phase.value, StockSheetPhase.idle);
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(c.thumbnails, isEmpty);
    expect(c.decoded.value, 0);
    expect(c.total.value, 0);
  });

  test('a decoder exception marks only that photo unreadable', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    })..throwFor.add('bad.jpg');
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['bad.jpg', 'a.jpg'], SheetFormat.excel);
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
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.thumbnails, isEmpty);
  });

  test('a share failure keeps the files and Share files retries it', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 1});
    shareError = Exception('no share sheet');
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);

    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, "Couldn't open the share sheet. Try again.");
    expect(c.files.single.name, 'Items-20261117-0905.xlsx');
    expect(File(c.files.single.path).existsSync(), isTrue);
    expect(shared, isEmpty);

    await c.shareAgain();
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(c.errorMessage.value, isNull);
    expect(c.sharing.value, isFalse);
    expect(provider.stockCalls, 1);
    expect(decoder.calls, 1);

    shareError = Exception('again');
    await c.shareAgain();
    expect(c.errorMessage.value, "Couldn't open the share sheet. Try again.");
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.sharing.value, isFalse);
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
      final run = c.start(['a.jpg', 'b.jpg'], SheetFormat.excel);
      await pumpEventQueue();
      expect(decoder.calls, 1);

      c.onClose();
      decoder.gate!.complete();
      await run;

      expect(decoder.calls, 1);
      expect(decoder.disposed, isTrue);
      expect(provider.stockCalls, 0);
      expect(shared, isEmpty);
      expect(written(), isEmpty);
      expect(c.busy.value, isFalse);
    });

    test('during the stock check: no share and no files', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final provider = _FakeProvider(stock: {_a: 1})
        ..stockGate = Completer<void>();
      final c = make(decoder, provider);
      final run = c.start(['a.jpg'], SheetFormat.both);
      await pumpEventQueue();
      expect(provider.stockCalls, 1);

      c.onClose();
      provider.stockGate!.complete();
      await run;

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
      final run = c.start(['a.jpg'], SheetFormat.both);
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
      await c.start(['a.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);

      c.onClose();
      await c.chooseOutOfStock(OutOfStockChoice.includeRed);

      expect(shared, isEmpty);
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
        c.takeShare([cached.path, nested.path, gallery.path, sneaky]),
        isTrue,
      );
      c.onClose();
      await pumpEventQueue();

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
      c.takeShare([first.path]);
      c.takeShare([second.path]);
      await c.start([second.path], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.done);
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);

      c.onClose();
      await pumpEventQueue();

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    test('a photo already gone does not stop the others', () async {
      final kept = photo(tmp, 'b.jpg');
      final c = make(_FakeDecoder({}), _FakeProvider());
      c.takeShare(['${tmp.path}/missing.jpg', kept.path]);
      c.onClose();
      await pumpEventQueue();
      expect(kept.existsSync(), isFalse);
    });
  });
}
