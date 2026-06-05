import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/image_scan/barcode_highlight_painter.dart';

void main() {
  group('BarcodeHighlightPainter.scalePoint — BoxFit.contain logic', () {
    // Image 1000×800, Render 300×300:
    // scaleX = 0.3, scaleY = 0.375 → scale = min = 0.3
    // offsetX = (300 - 1000*0.3) / 2 = 0
    // offsetY = (300 - 800*0.3)  / 2 = (300 - 240) / 2 = 30 (letterbox)
    const image = Size(1000, 800);
    const render = Size(300, 300);

    test('top-left corner → render origin + letterbox offsetY', () {
      final result = BarcodeHighlightPainter.scalePoint(
          Offset.zero, image, render);
      expect(result.dx, closeTo(0.0, 0.001));
      expect(result.dy, closeTo(30.0, 0.001));
    });

    test('bottom-right corner fills render width, fits inside height', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(1000, 800), image, render);
      expect(result.dx, closeTo(300.0, 0.001));
      expect(result.dy, closeTo(270.0, 0.001)); // 800*0.3 + 30 = 270
    });

    test('centre of image maps to centre of render', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(500, 400), image, render);
      expect(result.dx, closeTo(150.0, 0.001));
      expect(result.dy, closeTo(150.0, 0.001)); // 400*0.3 + 30 = 150
    });

    test('pillarbox — tall image, wide render', () {
      // Image 800×1000, Render 300×300:
      // scaleX = 0.375, scaleY = 0.3 → scale = 0.3
      // offsetX = (300 - 800*0.3) / 2 = 30, offsetY = 0
      final result = BarcodeHighlightPainter.scalePoint(
          Offset.zero,
          const Size(800, 1000),
          const Size(300, 300));
      expect(result.dx, closeTo(30.0, 0.001));
      expect(result.dy, closeTo(0.0, 0.001));
    });

    test('exact fit — no offset', () {
      final result = BarcodeHighlightPainter.scalePoint(
          const Offset(150, 150),
          const Size(300, 300),
          const Size(300, 300));
      expect(result.dx, closeTo(150.0, 0.001));
      expect(result.dy, closeTo(150.0, 0.001));
    });
  });
}
