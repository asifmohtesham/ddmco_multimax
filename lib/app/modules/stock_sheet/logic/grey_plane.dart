import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:image/image.dart' as img;

/// A greyscale picture held as one byte per pixel, row by row.
///
/// The copies of a photo that are read for barcodes (the tiles of
/// `SheetReading`, the 2x copy of `MlKitPhotoDecoder`) are cut and enlarged
/// here instead of with the `image` package, which takes seconds for each
/// enlarged megapixel on a phone. The results are **exactly** the package's
/// pixels (`test/unit/grey_plane_test.dart` compares them), so a code that
/// was read from the package's copy is read from this one.
class GreyPlane {
  GreyPlane(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  /// The plane of an image that is already greyscale: its red channel.
  factory GreyPlane.of(img.Image greyscale) {
    final source = greyscale.format == img.Format.uint8 && !greyscale.hasPalette
        ? greyscale
        : greyscale.convert(format: img.Format.uint8, numChannels: 3);
    final width = source.width;
    final height = source.height;
    final bytes = source.toUint8List();
    final channels = source.numChannels;
    final stride = source.rowStride;
    final pixels = Uint8List(width * height);
    var o = 0;
    for (var y = 0; y < height; y++) {
      var i = y * stride;
      for (var x = 0; x < width; x++, i += channels) {
        pixels[o++] = bytes[i];
      }
    }
    return GreyPlane(width, height, pixels);
  }

  /// The photo in [bytes], upright (its EXIF orientation applied) and
  /// greyscale; null when the bytes are not an image the package reads.
  static GreyPlane? decode(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      // The package throws on some corrupt data instead of returning null.
    }
    if (decoded == null) return null;
    return GreyPlane.of(img.grayscale(img.bakeOrientation(decoded)));
  }

  /// The [w] x [h] part whose top-left corner is at ([x], [y]).
  GreyPlane crop(int x, int y, int w, int h) {
    final out = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      final from = (y + row) * width + x;
      out.setRange(row * w, row * w + w, pixels, from);
    }
    return GreyPlane(w, h, out);
  }

  /// Enlarged to [w] x [h] by repeating pixels (the package's `nearest`):
  /// every bar edge stays as sharp as it was.
  GreyPlane enlargedSharp(int w, int h) {
    final out = Uint8List(w * h);
    final dx = width / w;
    final dy = height / h;
    final columns = Int32List(w);
    for (var x = 0; x < w; x++) {
      columns[x] = (x * dx).toInt();
    }
    var previous = -1;
    for (var y = 0; y < h; y++) {
      final o = y * w;
      final sourceRow = (y * dy).toInt();
      if (sourceRow == previous) {
        out.setRange(o, o + w, out, o - w);
        continue;
      }
      final from = sourceRow * width;
      for (var x = 0; x < w; x++) {
        out[o + x] = pixels[from + columns[x]];
      }
      previous = sourceRow;
    }
    return GreyPlane(w, h, out);
  }

  /// Enlarged to [w] x [h] with smoothing (the package's `cubic`, a
  /// Catmull-Rom curve through four pixels each way).
  ///
  /// Away from the edges the curve along a source row does not depend on the
  /// output row, so each source row is worked out once and shared by the
  /// output rows that use it. At the edges the package stands in the centre
  /// pixel for a missing neighbour; [_edge] follows it line by line.
  GreyPlane enlargedSmooth(int w, int h) {
    final out = Uint8List(w * h);
    final dx = width / w;
    final dy = height / h;

    // For each output column: its source column, and how far past it the
    // output pixel lies (with that distance squared and cubed).
    final column = Int32List(w);
    final fx = Float64List(w);
    final fx2 = Float64List(w);
    final fx3 = Float64List(w);
    // The output columns whose four source columns all exist.
    var firstInner = w;
    var lastInner = -1;
    for (var x = 0; x < w; x++) {
      final f = x * dx;
      final source = f.toInt();
      final d = f - source;
      column[x] = source;
      fx[x] = d;
      fx2[x] = d * d;
      fx3[x] = d * d * d;
      if (source >= 1 && source + 2 < width) {
        if (firstInner == w) firstInner = x;
        lastInner = x;
      }
    }

    // The curve along the four source rows in use, kept by row number.
    final across = [for (var i = 0; i < 4; i++) Float64List(w)];
    final held = [-1, -1, -1, -1];
    Float64List along(int row) {
      final slot = row & 3;
      final values = across[slot];
      if (held[slot] == row) return values;
      final from = row * width;
      for (var x = firstInner; x <= lastInner; x++) {
        final i = from + column[x];
        final p = pixels[i - 1];
        final c = pixels[i];
        final n = pixels[i + 1];
        final a = pixels[i + 2];
        values[x] =
            c +
            0.5 *
                (fx[x] * (-p + n) +
                    fx2[x] * (2 * p - 5 * c + 4 * n - a) +
                    fx3[x] * (-p + 3 * c - 3 * n + a));
      }
      held[slot] = row;
      return values;
    }

    for (var y = 0; y < h; y++) {
      final f = y * dy;
      final source = f.toInt();
      final d = f - source;
      final o = y * w;
      if (source < 1 || source + 2 >= height || lastInner < firstInner) {
        for (var x = 0; x < w; x++) {
          out[o + x] = _edge(column[x], source, fx[x], d);
        }
        continue;
      }
      final d2 = d * d;
      final d3 = d * d * d;
      final p = along(source - 1);
      final c = along(source);
      final n = along(source + 1);
      final a = along(source + 2);
      for (var x = 0; x < firstInner; x++) {
        out[o + x] = _edge(column[x], source, fx[x], d);
      }
      for (var x = firstInner; x <= lastInner; x++) {
        final value =
            c[x] +
            0.5 *
                (d * (-p[x] + n[x]) +
                    d2 * (2 * p[x] - 5 * c[x] + 4 * n[x] - a[x]) +
                    d3 * (-p[x] + 3 * c[x] - 3 * n[x] + a[x]));
        out[o + x] = _toByte(value);
      }
      for (var x = lastInner + 1; x < w; x++) {
        out[o + x] = _edge(column[x], source, fx[x], d);
      }
    }
    return GreyPlane(w, h, out);
  }

  static int _toByte(double value) {
    final whole = value.toInt();
    return whole < 0 ? 0 : (whole > 255 ? 255 : whole);
  }

  static double _curve(double d, double p, double c, double n, double a) =>
      c +
      0.5 *
          (d * (-p + n) +
              d * d * (2 * p - 5 * c + 4 * n - a) +
              d * d * d * (-p + 3 * c - 3 * n + a));

  /// The smoothed value at source pixel ([x], [y]) plus ([dx], [dy]), where
  /// some of the sixteen pixels around it lie outside the picture. Each
  /// condition is the package's own (`Image.getPixelCubic`), including the
  /// row above the top edge reading as black under the centre column.
  int _edge(int x, int y, double dx, double dy) {
    final px = x - 1;
    final nx = x + 1;
    final ax = x + 2;
    final py = y - 1;
    final ny = y + 1;
    final ay = y + 2;
    double at(int x, int y) => x < 0 || x >= width || y < 0 || y >= height
        ? 0
        : pixels[y * width + x].toDouble();

    final cc = at(x, y);
    final above = _curve(
      dx,
      px < 0 || py < 0 ? cc : at(px, py),
      px < 0 ? cc : at(x, py),
      py < 0 || nx >= width ? cc : at(nx, py),
      ax >= width || py < 0 ? cc : at(ax, py),
    );
    final centre = _curve(
      dx,
      px < 0 ? cc : at(px, y),
      cc,
      nx >= width ? cc : at(nx, y),
      ax >= width ? cc : at(ax, y),
    );
    final below = _curve(
      dx,
      px < 0 || ny >= height ? cc : at(px, ny),
      ny >= height ? cc : at(x, ny),
      nx >= width || ny >= height ? cc : at(nx, ny),
      ax >= width || ny >= height ? cc : at(ax, ny),
    );
    final after = _curve(
      dx,
      px < 0 || ay >= height ? cc : at(px, ay),
      ay >= height ? cc : at(x, ay),
      nx >= width || ay >= height ? cc : at(nx, ay),
      ax >= width || ay >= height ? cc : at(ax, ay),
    );
    return _toByte(_curve(dy, above, centre, below, after));
  }

  /// The plane as a PNG with red, green and blue all set to the grey value
  /// (the picture the package writes for a greyscale photo), lightly
  /// compressed: these files are read once and deleted. Written here because
  /// the package's encoder spends most of its time filtering rows in Dart;
  /// this hands the rows straight to the platform's zlib.
  Uint8List toPng({int level = 1}) {
    final raw = Uint8List((1 + width * 3) * height);
    var i = 0;
    var o = 0;
    for (var y = 0; y < height; y++) {
      o++; // Filter type 0: the row as it is.
      for (var x = 0; x < width; x++, o += 3) {
        final v = pixels[i++];
        raw[o] = v;
        raw[o + 1] = v;
        raw[o + 2] = v;
      }
    }
    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8) // Bits per channel.
      ..setUint8(9, 2); // Colour type: RGB.
    final out = BytesBuilder(copy: false)
      ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    Uint8List uint32(int value) =>
        (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
    void chunk(String type, List<int> data) {
      final name = type.codeUnits;
      out
        ..add(uint32(data.length))
        ..add(name)
        ..add(data)
        ..add(uint32(getCrc32(data, getCrc32(name))));
    }

    chunk('IHDR', header.buffer.asUint8List());
    chunk('IDAT', ZLibCodec(level: level).encode(raw));
    chunk('IEND', const []);
    return out.takeBytes();
  }
}
