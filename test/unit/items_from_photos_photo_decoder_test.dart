import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

Uint8List _png(int w, int h) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

void main() {
  group('headerSize', () {
    test('reads JPEG and PNG sizes', () {
      expect(MlKitPhotoDecoder.headerSize(_jpeg(2400, 10)), (
        width: 2400,
        height: 10,
      ));
      expect(MlKitPhotoDecoder.headerSize(_png(30, 2000)), (
        width: 30,
        height: 2000,
      ));
    });

    test('needs only the header, not the pixels', () {
      final full = _jpeg(2400, 1800);
      // The frame header sits well inside the first kilobyte; the rest of
      // the scan data is cut off, so a full decode would fail.
      final cut = Uint8List.fromList(full.sublist(0, 1024));
      img.Image? decoded;
      try {
        decoded = img.decodeJpg(cut);
      } catch (_) {}
      expect(decoded, isNull);
      expect(MlKitPhotoDecoder.headerSize(cut), (width: 2400, height: 1800));
    });

    test('null for bytes that are not an image', () {
      expect(
        MlKitPhotoDecoder.headerSize(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });
  });

  group('upscaledCopy', () {
    test('a small photo becomes a 2x greyscale PNG', () {
      final source = img.Image(width: 30, height: 20);
      img.fill(source, color: img.ColorRgb8(200, 40, 40));
      final copy = MlKitPhotoDecoder.upscaledCopy(
        Uint8List.fromList(img.encodePng(source)),
      );
      final decoded = img.decodePng(copy!)!;
      expect([decoded.width, decoded.height], [60, 40]);
      final p = decoded.getPixel(30, 20);
      expect(p.r, p.g);
      expect(p.g, p.b);
    });

    test('a long side of 2000 px or more is skipped', () {
      expect(MlKitPhotoDecoder.upscaledCopy(_png(2000, 10)), isNull);
      expect(MlKitPhotoDecoder.upscaledCopy(_jpeg(10, 2400)), isNull);
      // Skipped on the header alone: these pixels could not be decoded.
      final cut = Uint8List.fromList(_jpeg(2400, 1800).sublist(0, 1024));
      expect(MlKitPhotoDecoder.upscaledCopy(cut), isNull);
    });

    test('null for bytes that are not an image', () {
      expect(
        MlKitPhotoDecoder.upscaledCopy(Uint8List.fromList([0, 1])),
        isNull,
      );
    });
  });
}
