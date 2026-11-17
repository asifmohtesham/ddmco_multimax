import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_aggregator.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_sheet_codec.dart';
import 'package:multimax/app/modules/stock_sheet/logic/thumbnail_maker.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/output/pdf_stock_sheet_writer.dart';
import 'package:multimax/app/modules/stock_sheet/output/xlsx_stock_sheet_writer.dart';

enum SheetFormat { excel, pdf, both }

enum OutOfStockChoice { includeRed, includePlain, leaveOut }

enum StockSheetPhase {
  idle,
  decoding,
  checkingStock,
  awaitingChoice,
  building,
  done,
  error,
}

/// Runs one "share photos to a stock sheet" job: decode, check stock, ask
/// about out-of-stock items, write the files and share them.
class StockSheetController extends GetxController {
  StockSheetController({
    PhotoDecoder Function()? decoderFactory,
    StockSheetProvider? provider,
    Future<void> Function(List<XFile>)? shareFiles,
    DateTime Function()? now,
    Future<Directory> Function()? tempDir,
    Future<Uint8List> Function(StockSheetDocument)? writePdf,
    Future<Uint8List?> Function(String)? makeThumbnail,
  }) : _decoderFactory = decoderFactory ?? MlKitPhotoDecoder.new,
       _provider = provider ?? StockSheetProvider(),
       _shareFiles = shareFiles ?? _defaultShare,
       _now = now ?? DateTime.now,
       _tempDir = tempDir ?? getTemporaryDirectory,
       _writePdf = writePdf ?? ((doc) => PdfStockSheetWriter.write(doc)),
       _makeThumbnail = makeThumbnail ?? ((path) => ThumbnailMaker.make(path));

  static const int maxPhotos = 100;
  static const String _title = 'Stock sheet';
  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String _pdfMime = 'application/pdf';

  static Future<void> _defaultShare(List<XFile> files) async {
    await SharePlus.instance.share(ShareParams(files: files));
  }

  final PhotoDecoder Function() _decoderFactory;
  final StockSheetProvider _provider;
  final Future<void> Function(List<XFile>) _shareFiles;
  final DateTime Function() _now;
  final Future<Directory> Function() _tempDir;
  final Future<Uint8List> Function(StockSheetDocument) _writePdf;
  final Future<Uint8List?> Function(String) _makeThumbnail;

  final busy = false.obs;
  final phase = StockSheetPhase.idle.obs;
  final decoded = 0.obs;
  final total = 0.obs;
  final errorMessage = RxnString();
  final result = Rxn<StockSheetResult>();
  final files = <XFile>[].obs;
  final thumbnails = <String, Uint8List>{}.obs;

  /// True while [shareAgain] is handing the files to the share sheet.
  final sharing = false.obs;

  /// The photos of the share on screen (see [takeShare]).
  final sharedPaths = <String>[].obs;

  /// Bumped by every [takeShare], so the screen asks for a format again.
  final shareSerial = 0.obs;

  List<PhotoScan> _scans = const [];
  SheetFormat _format = SheetFormat.excel;
  final List<File> _created = [];

  Future<void> start(List<String> paths, SheetFormat format) async {
    if (busy.value) return;
    busy.value = true;
    try {
      _clear();
      _format = format;
      if (paths.length > maxPhotos) {
        errorMessage.value =
            'Share up to $maxPhotos photos at a time (you shared ${paths.length}).';
        phase.value = StockSheetPhase.error;
        return;
      }
      total.value = paths.length;
      phase.value = StockSheetPhase.decoding;
      try {
        await _decodeAll(paths);
      } on UnsupportedError {
        _fail("Reading barcodes from photos isn't supported on this device.");
        return;
      }
      await _checkStock();
    } finally {
      busy.value = false;
    }
  }

  Future<void> retry() async {
    if (busy.value || _scans.isEmpty) return;
    busy.value = true;
    try {
      errorMessage.value = null;
      await _checkStock();
    } finally {
      busy.value = false;
    }
  }

  Future<void> chooseOutOfStock(OutOfStockChoice? choice) async {
    if (busy.value || phase.value != StockSheetPhase.awaitingChoice) return;
    final current = result.value;
    if (choice == null || current == null) {
      result.value = null;
      phase.value = StockSheetPhase.idle;
      return;
    }
    busy.value = true;
    try {
      final rows = choice == OutOfStockChoice.leaveOut
          ? current.rows.where((r) => !r.outOfStock).toList()
          : current.rows;
      await _build(
        rows,
        current.outOfStockCount,
        highlight: choice == OutOfStockChoice.includeRed,
        showStatus: choice != OutOfStockChoice.leaveOut,
      );
    } finally {
      busy.value = false;
    }
  }

  Future<void> shareAgain() async {
    if (sharing.value || files.isEmpty) return;
    sharing.value = true;
    try {
      await _shareFiles(files.toList());
    } finally {
      sharing.value = false;
    }
  }

  /// True when [retry] can rerun the ERP step: the photos were decoded.
  bool get canRetry => _scans.isNotEmpty;

  /// Takes the photos of a new share and starts over, ready for the format
  /// question. Refused (returns false, nothing changes) while a run is active.
  bool takeShare(List<String> paths) {
    if (busy.value) return false;
    reset();
    sharedPaths.assignAll(paths);
    shareSerial.value++;
    return true;
  }

  /// Back to a blank slate for a new share. Ignored while a run is active.
  void reset() {
    if (busy.value) return;
    _clear();
    decoded.value = 0;
    total.value = 0;
    phase.value = StockSheetPhase.idle;
  }

  @override
  void onClose() {
    _deleteCreatedFiles();
    super.onClose();
  }

  void _clear() {
    _deleteCreatedFiles();
    result.value = null;
    files.clear();
    thumbnails.clear();
    errorMessage.value = null;
    _scans = const [];
  }

  void _deleteCreatedFiles() {
    for (final file in _created) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // Best effort: the OS clears the temp folder eventually.
      }
    }
    _created.clear();
  }

  void _log(String what, Object e, StackTrace st) {
    if (kDebugMode) debugPrint('StockSheetController: $what: $e\n$st');
  }

  void _fail(String message) {
    errorMessage.value = message;
    phase.value = StockSheetPhase.error;
  }

  Future<void> _decodeAll(List<String> paths) async {
    final decoder = _decoderFactory();
    final scans = <PhotoScan>[];
    try {
      for (var i = 0; i < paths.length; i++) {
        final path = paths[i];
        List<String>? raw;
        try {
          raw = await decoder.decode(path);
        } on UnsupportedError {
          rethrow;
        } catch (e, st) {
          _log('decode failed for $path', e, st);
        }
        scans.add(
          raw == null
              ? PhotoScan(index: i, path: path, decodeFailed: true)
              : PhotoScan(
                  index: i,
                  path: path,
                  rawValues: raw,
                  items: StockSheetCodec.itemsInPhoto(raw),
                ),
        );
        try {
          final thumb = await _makeThumbnail(path);
          if (thumb != null) thumbnails[path] = thumb;
        } catch (e, st) {
          _log('thumbnail failed for $path', e, st);
        }
        decoded.value = i + 1;
      }
    } finally {
      await decoder.dispose();
    }
    _scans = scans;
  }

  /// The ERP step: items, stock, then either ask or build.
  Future<void> _checkStock() async {
    phase.value = StockSheetPhase.checkingStock;
    try {
      final codes = <String>{
        for (final scan in _scans)
          for (final item in scan.items) item.itemCode,
      }.toList();
      final items = codes.isEmpty
          ? <String, ItemInfo>{}
          : await _provider.fetchItems(codes);
      final stockRows = codes.isEmpty
          ? <Map<String, dynamic>>[]
          : await _provider.fetchFinishedGoodsStock(codes);
      final built = StockAggregator.build(
        _scans,
        items,
        StockAggregator.sumByItem(stockRows),
      );
      result.value = built;
      if (built.outOfStockCount > 0) {
        phase.value = StockSheetPhase.awaitingChoice;
        return;
      }
      await _build(built.rows, 0, highlight: false, showStatus: false);
    } on StockAccessDenied {
      _fail("You don't have access to stock levels.");
    } catch (e, st) {
      _log('stock check failed', e, st);
      _fail("Couldn't reach the ERP. Check the connection and try again.");
    }
  }

  Future<void> _build(
    List<StockSheetRow> rows,
    int outOfStockCount, {
    required bool highlight,
    required bool showStatus,
  }) async {
    phase.value = StockSheetPhase.building;
    try {
      final now = _now();
      final subtitle =
          '${DateFormat('dd/MM/yyyy HH:mm').format(now)}'
          ' · ${_scans.length} photos · ${rows.length} items'
          ' · $outOfStockCount out of stock';
      final doc = StockSheetDocument(
        title: _title,
        subtitle: subtitle,
        rows: rows,
        thumbnails: Map<String, Uint8List>.of(thumbnails),
        highlightOutOfStock: highlight,
        showStatus: showStatus,
      );
      files.clear();
      _deleteCreatedFiles();
      if (rows.isNotEmpty) {
        final dir = await _tempDir();
        final stamp = DateFormat('yyyyMMdd-HHmm').format(now);
        if (_format != SheetFormat.pdf) {
          files.add(
            await _store(
              dir,
              'stock-sheet-$stamp.xlsx',
              XlsxStockSheetWriter.write(doc),
              _xlsxMime,
            ),
          );
        }
        if (_format != SheetFormat.excel) {
          files.add(
            await _store(
              dir,
              'stock-sheet-$stamp.pdf',
              await _writePdf(doc),
              _pdfMime,
            ),
          );
        }
        await _shareFiles(files.toList());
      }
      phase.value = StockSheetPhase.done;
    } catch (e, st) {
      _log('build failed', e, st);
      _fail("Couldn't build the sheet. Try again.");
    }
  }

  Future<XFile> _store(
    Directory dir,
    String name,
    Uint8List bytes,
    String mime,
  ) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    _created.add(file);
    return XFile(file.path, mimeType: mime, name: name);
  }
}
