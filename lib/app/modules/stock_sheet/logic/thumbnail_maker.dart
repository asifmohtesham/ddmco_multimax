import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Makes small JPEG thumbnails for the sheet's Image column.
class ThumbnailMaker {
  const ThumbnailMaker._();

  /// Returns a JPEG whose long side is at most [longSide], keeping the aspect
  /// ratio, or `null` when the file cannot be decoded. The engine applies the
  /// EXIF orientation while decoding.
  static Future<Uint8List?> make(
    String path, {
    int longSide = 480,
    int quality = 82,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
    return fromBytes(bytes, longSide: longSide, quality: quality);
  }

  /// [make] for an image already in memory, such as an Item's ERP image.
  static Future<Uint8List?> fromBytes(
    Uint8List bytes, {
    int longSide = 480,
    int quality = 82,
  }) async {
    ui.Image? decoded;
    try {

      // First pass reads only the header, to learn which side is the long one.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final int width;
      final int height;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        width = descriptor.width;
        height = descriptor.height;
        descriptor.dispose();
      } finally {
        buffer.dispose();
      }

      // Pass one dimension only so the engine keeps the aspect ratio. Never
      // upscale a small photo.
      final landscape = width >= height;
      final long = landscape ? width : height;
      final target = long > longSide ? longSide : long;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: landscape ? target : null,
        targetHeight: landscape ? null : target,
      );
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }

      final data = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final w = decoded.width;
      final h = decoded.height;
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      return await Isolate.run(() {
        final image = img.Image.fromBytes(
          width: w,
          height: h,
          bytes: rgba.buffer,
          bytesOffset: rgba.offsetInBytes,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
        return Uint8List.fromList(img.encodeJpg(image, quality: quality));
      });
    } catch (_) {
      return null;
    } finally {
      decoded?.dispose();
    }
  }
}
