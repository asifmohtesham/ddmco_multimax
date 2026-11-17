import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import 'stock_sheet_codec.dart';

/// Reads the barcodes in one photo.
abstract class PhotoDecoder {
  /// Returns the raw barcode values found in the photo: an empty list when
  /// there are none, `null` when the image cannot be read.
  Future<List<String>?> decode(String path);

  Future<void> dispose();
}

/// On-device decoding with ML Kit, through `mobile_scanner`.
class MlKitPhotoDecoder implements PhotoDecoder {
  MlKitPhotoDecoder() : _scanner = MobileScannerController(autoStart: false);

  static const _formats = [
    BarcodeFormat.ean8,
    BarcodeFormat.ean13,
    BarcodeFormat.qrCode,
    BarcodeFormat.code128,
    BarcodeFormat.dataMatrix,
  ];

  /// Photos at least this wide or tall are not worth upscaling.
  static const _skipUpscaleAt = 2000;

  final MobileScannerController _scanner;

  @override
  Future<List<String>?> decode(String path) async {
    try {
      final first = await _analyse(path);
      if (_anyClassifies(first)) return first;

      final retry = await _retryUpscaled(path);
      return retry != null && _anyClassifies(retry) ? retry : first;
    } on UnsupportedError {
      // Simulators have no ML Kit; the controller shows a clear message.
      rethrow;
    } on MobileScannerBarcodeException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _analyse(String path) async {
    final capture = await _scanner.analyzeImage(path, formats: _formats);
    if (capture == null) return const [];
    return [
      for (final barcode in capture.barcodes)
        if ((barcode.rawValue ?? '').isNotEmpty) barcode.rawValue!,
    ];
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
    final source = img.decodeImage(bytes);
    if (source == null) return null;
    final resized = img.copyResize(
      img.grayscale(source),
      width: source.width * 2,
      height: source.height * 2,
      interpolation: img.Interpolation.cubic,
    );
    return img.encodePng(resized);
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
      final dir = await getTemporaryDirectory();
      final target = File(
        '${dir.path}/stock_sheet_retry_${DateTime.now().microsecondsSinceEpoch}.png',
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
  Future<void> dispose() => _scanner.dispose();
}
