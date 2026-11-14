import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Draws bounding-box overlays over detected barcodes, scaled to match a
/// [BoxFit.contain] image rendered inside the paint area.
class BarcodeHighlightPainter extends CustomPainter {
  final List<Barcode> barcodes;
  final int? selectedIndex;

  /// Natural pixel dimensions of the source image.
  final Size imageSize;

  const BarcodeHighlightPainter({
    required this.barcodes,
    required this.imageSize,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;

    for (var i = 0; i < barcodes.length; i++) {
      final corners = barcodes[i].corners;
      if (corners == null || corners.isEmpty) continue;

      final isSelected = selectedIndex == i;
      final paint = Paint()
        ..color = isSelected ? Colors.greenAccent : Colors.orangeAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0;

      final path = Path();
      final pts = corners
          .map((p) => scalePoint(Offset(p.dx, p.dy), imageSize, size))
          .toList();
      path.moveTo(pts[0].dx, pts[0].dy);
      for (var j = 1; j < pts.length; j++) {
        path.lineTo(pts[j].dx, pts[j].dy);
      }
      path.close();
      canvas.drawPath(path, paint);

      // Label (index) near top-left corner of box
      final labelOffset = pts[0] + const Offset(4, -18);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: isSelected ? Colors.greenAccent : Colors.orangeAccent,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(BarcodeHighlightPainter old) =>
      old.barcodes != barcodes ||
      old.selectedIndex != selectedIndex ||
      old.imageSize != imageSize;

  /// Scales [point] from natural image pixel coordinates to [renderSize]
  /// applying BoxFit.contain logic: uniform scale, centred with letterbox or
  /// pillarbox offset.
  ///
  /// Exposed as a static method so it can be tested without a canvas.
  static Offset scalePoint(Offset point, Size imageSize, Size renderSize) {
    final scaleX = renderSize.width / imageSize.width;
    final scaleY = renderSize.height / imageSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (renderSize.width - imageSize.width * scale) / 2;
    final offsetY = (renderSize.height - imageSize.height * scale) / 2;
    return Offset(point.dx * scale + offsetX, point.dy * scale + offsetY);
  }
}
