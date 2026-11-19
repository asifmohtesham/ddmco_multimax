import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'grey_plane.dart';
import 'sheet_reading.dart';
import 'stock_sheet_codec.dart';

/// One code the platform found in an image file: its text, and its corners
/// in that image's pixels (none when the platform gives none).
typedef AnalysedCode = ({String value, List<({double x, double y})> corners});

/// Reads the codes in the image file at a path: ML Kit in the app, a fake in
/// tests.
typedef PhotoAnalyser = Future<List<AnalysedCode>> Function(String path);

/// Reads the barcodes in one photo, in two rounds: the whole photo, then,
/// when that did not settle it, tiles of it.
abstract class PhotoDecoder {
  /// Round one: the whole photo. The raw barcode values found: an empty list
  /// when there are none, `null` when the photo cannot be read.
  Future<List<String>?> readWhole(String path);

  /// Round two: tiles, then the 2x copy for a small photo that still has no
  /// item. [whole] is what [readWhole] gave. `null` when [stopped] said so
  /// (it is asked before each read) or when the photo cannot be read.
  Future<List<String>?> zoomIn(
    String path, {
    required List<String> whole,
    bool Function()? stopped,
  });

  /// True unless [whole] holds exactly one item: one label (an EAN-8 and its
  /// batch QR count as one item) is read in full by round one.
  static bool needsZoom(List<String> whole) =>
      StockSheetCodec.itemsInPhoto(whole).length != 1;

  Future<void> dispose();
}

/// On-device decoding with ML Kit, through `mobile_scanner`.
class MlKitPhotoDecoder extends PhotoDecoder {
  /// [analyser] and [temporaryPath] are for tests; the app leaves both out
  /// and gets ML Kit and the system's temporary folder.
  MlKitPhotoDecoder({
    PhotoAnalyser? analyser,
    Future<String> Function()? temporaryPath,
  }) : _temporaryPath = temporaryPath ?? _systemTemporaryPath {
    if (analyser != null) {
      _scanner = null;
      _analyser = analyser;
    } else {
      final scanner = MobileScannerController(autoStart: false);
      _scanner = scanner;
      _analyser = (path) => _analyseWithMlKit(scanner, path);
    }
  }

  static const _formats = [
    BarcodeFormat.ean8,
    BarcodeFormat.ean13,
    BarcodeFormat.qrCode,
    BarcodeFormat.code128,
    BarcodeFormat.dataMatrix,
  ];

  /// Photos at least this wide or tall are not worth upscaling.
  static const _skipUpscaleAt = 2000;

  late final MobileScannerController? _scanner;
  late final PhotoAnalyser _analyser;
  final Future<String> Function() _temporaryPath;

  static Future<String> _systemTemporaryPath() async =>
      (await getTemporaryDirectory()).path;

  static Future<List<AnalysedCode>> _analyseWithMlKit(
    MobileScannerController scanner,
    String path,
  ) async {
    final capture = await scanner.analyzeImage(path, formats: _formats);
    if (capture == null) return const [];
    return [
      for (final barcode in capture.barcodes)
        (
          value: barcode.rawValue ?? '',
          corners: [for (final c in barcode.corners) (x: c.dx, y: c.dy)],
        ),
    ];
  }

  @override
  Future<List<String>?> readWhole(String path) async {
    try {
      return await _analyse(path);
    } on UnsupportedError {
      // Simulators have no ML Kit; the controller shows a clear message.
      rethrow;
    } on MobileScannerBarcodeException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>?> zoomIn(
    String path, {
    required List<String> whole,
    bool Function()? stopped,
  }) async {
    try {
      final items = StockSheetCodec.itemsInPhoto(whole).length;
      // Two or more items mean a sheet of labels; no item at all is most
      // often a label too small to be found in the whole photo (a product
      // card with one small EAN-8). Both are read again in tiles.
      final tiles = await _readTiles(path, stopped);
      if (tiles.stopped) return null;
      final tiled = tiles.found;
      if (tiled != null) {
        final all = SheetReading.inReadingOrder([
          ...tiled,
          for (final value in whole) FoundCode(value),
        ]);
        if (items >= 2 || _anyClassifies(all)) return all;
      }
      if (items >= 2) return whole;
      // Last resort for a small photo: one label larger than a tile (over
      // 40% of the photo) that only reads enlarged.
      final retry = await _retryUpscaled(path);
      return retry != null && _anyClassifies(retry) ? retry : whole;
    } on UnsupportedError {
      rethrow;
    } on MobileScannerBarcodeException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _analyse(String path) async => [
    for (final found in await _analyseFound(path)) found.value,
  ];

  /// The codes in the image at [path], each with its box in that image's
  /// pixels when the platform gives corners.
  Future<List<FoundCode>> _analyseFound(
    String path, [
    ({int x, int y, double scale}) tile = (x: 0, y: 0, scale: 1),
  ]) async {
    return [
      for (final code in await _analyser(path))
        if (code.value.isNotEmpty)
          FoundCode(code.value, SheetReading.boxInPhoto(code.corners, tile)),
    ];
  }

  /// Reads the photo again in overlapping, enlarged tiles (see
  /// [SheetReading]). Returns what the tiles held, with boxes in the upright
  /// photo, or null when no tile could be made. A tile that cannot be read
  /// is skipped. [stopped] is asked once the tiles are written and before
  /// each read; when it says so, the result is `stopped` and the tile files
  /// are still deleted.
  Future<({List<FoundCode>? found, bool stopped})> _readTiles(
    String path,
    bool Function()? stopped,
  ) async {
    var tiles = const <SheetTile>[];
    try {
      final bytes = await File(path).readAsBytes();
      final dir = await _temporaryPath();
      final stem = 'stock_sheet_tile_${DateTime.now().microsecondsSinceEpoch}';
      tiles = await Isolate.run(
        () => SheetReading.writeTiles(bytes, dir, stem),
      );
      if (stopped?.call() ?? false) return (found: null, stopped: true);
      if (tiles.isEmpty) return (found: null, stopped: false);
      final found = <FoundCode>[];
      for (final tile in tiles) {
        if (stopped?.call() ?? false) return (found: null, stopped: true);
        try {
          found.addAll(
            await _analyseFound(tile.path, (
              x: tile.x,
              y: tile.y,
              scale: tile.scale,
            )),
          );
        } on UnsupportedError {
          rethrow;
        } catch (_) {
          // One unreadable tile leaves the others' codes.
        }
      }
      return (found: found, stopped: false);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      return (found: null, stopped: false);
    } finally {
      for (final tile in tiles) {
        try {
          await File(tile.path).delete();
        } catch (_) {}
      }
    }
  }

  bool _anyClassifies(List<String> values) =>
      values.any((raw) => StockSheetCodec.classify(raw) != null);

  /// The pixel size from the image header alone, without decoding the
  /// pixels; `null` when the bytes are not an image the package reads.
  @visibleForTesting
  static ({int width, int height})? headerSize(Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width <= 0 || info.height <= 0) return null;
      return (width: info.width, height: info.height);
    } catch (_) {
      return null;
    }
  }

  static bool _worthUpscaling(({int width, int height}) size) =>
      size.width < _skipUpscaleAt && size.height < _skipUpscaleAt;

  /// A 2x greyscale PNG of [bytes], or `null` when the photo is unreadable
  /// or already has a side of at least 2000 px. The size is checked from
  /// the header first, so a large photo is never decoded.
  @visibleForTesting
  static Uint8List? upscaledCopy(Uint8List bytes) {
    final size = headerSize(bytes);
    if (size == null || !_worthUpscaling(size)) return null;
    final source = GreyPlane.decode(bytes);
    if (source == null) return null;
    return source.enlargedSmooth(source.width * 2, source.height * 2).toPng();
  }

  /// One retry on a 2x greyscale copy. Returns `null` when no copy was made.
  Future<List<String>?> _retryUpscaled(String path) async {
    File? copy;
    try {
      final bytes = await File(path).readAsBytes();
      // Most camera photos are this large: skip them on the header alone,
      // without starting an isolate.
      final size = headerSize(bytes);
      if (size == null || !_worthUpscaling(size)) return null;
      final png = await Isolate.run(() => upscaledCopy(bytes));
      if (png == null) return null;
      final dir = await _temporaryPath();
      final target = File(
        '$dir/stock_sheet_retry_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      copy = await target.writeAsBytes(png);
      return await _analyse(copy.path);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      return null;
    } finally {
      try {
        await copy?.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async => _scanner?.dispose();
}
