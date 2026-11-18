import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Where a code sits in the photo, in the upright photo's pixels.
typedef CodeBox = ({double left, double top, double width, double height});

/// One value read from a photo, with its box when the platform gave one.
class FoundCode {
  const FoundCode(this.value, [this.box]);

  final String value;
  final CodeBox? box;
}

/// One tile cut from a photo: the file it was written to, where its top-left
/// corner sits in the upright photo, and how much it was enlarged.
typedef SheetTile = ({String path, int x, int y, double scale});

/// Reading a photo that holds a sheet of labels: the photo is read again in
/// overlapping tiles, so small codes the whole-photo pass missed are found,
/// and the codes are put in reading order (rows top to bottom, each row left
/// to right), the order a person checks the sheet in.
class SheetReading {
  const SheetReading._();

  /// Tiles per side. Each tile spans [_tileFraction] of the side and starts
  /// [_strideFraction] after the previous one, so any label up to 40% of the
  /// photo's width and height lies whole inside at least one tile.
  static const int _grid = 3;
  static const double _tileFraction = 0.6;
  static const double _strideFraction = 0.2;

  /// A tile whose long side is under this is enlarged (at most 4x), so the
  /// bars of a small code are several pixels wide.
  static const int _minTileSide = 1200;

  /// The tiles of a [width] x [height] photo, row by row.
  static List<({int x, int y, int width, int height})> tileRects(
    int width,
    int height,
  ) {
    final tw = (width * _tileFraction).round();
    final th = (height * _tileFraction).round();
    return [
      for (var row = 0; row < _grid; row++)
        for (var col = 0; col < _grid; col++)
          (
            // The last tile ends on the edge whatever the rounding.
            x: col == _grid - 1
                ? width - tw
                : (width * _strideFraction * col).round(),
            y: row == _grid - 1
                ? height - th
                : (height * _strideFraction * row).round(),
            width: tw,
            height: th,
          ),
    ];
  }

  /// How much a tile with long side [longSide] is enlarged.
  static double scaleFor(int longSide) {
    if (longSide <= 0 || longSide >= _minTileSide) return 1;
    return math.min(4, (_minTileSide / longSide).ceilToDouble());
  }

  /// Decodes [bytes] upright and greyscale, cuts the tiles and writes each to
  /// [dir] as a PNG; an enlarged tile twice, smooth and sharp (see below).
  /// Returns none when the bytes are not an image. Runs in a
  /// background isolate: decoding a camera photo takes a second or more.
  static List<SheetTile> writeTiles(Uint8List bytes, String dir, String stem) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      // The package throws on some corrupt data instead of returning null.
    }
    if (decoded == null) return const [];
    final upright = img.grayscale(img.bakeOrientation(decoded));
    final tiles = <SheetTile>[];
    final rects = tileRects(upright.width, upright.height);
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      var tile = img.copyCrop(
        upright,
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
      );
      final scale = scaleFor(math.max(r.width, r.height));
      void write(img.Image copy, String suffix) {
        final path = '$dir/${stem}_$i$suffix.png';
        File(path).writeAsBytesSync(img.encodePng(copy, level: 1));
        tiles.add((path: path, x: r.x, y: r.y, scale: scale));
      }

      if (scale == 1) {
        write(tile, '');
        continue;
      }
      // An enlarged tile is written twice. Smoothing (cubic) helps a blurred
      // camera photo; on a small sharp image, such as a WhatsApp copy of a
      // printed sheet, it blends bars only one or two pixels wide into grey
      // and a code is lost, while repeating each pixel (nearest, exact for
      // the whole-number scale) keeps every bar edge. Each copy finds codes
      // the other misses; the caller keeps what either finds.
      for (final (interpolation, suffix) in [
        (img.Interpolation.cubic, 's'),
        (img.Interpolation.nearest, 'n'),
      ]) {
        write(
          img.copyResize(
            tile,
            width: (r.width * scale).round(),
            height: (r.height * scale).round(),
            interpolation: interpolation,
          ),
          suffix,
        );
      }
    }
    return tiles;
  }

  /// The box of a code found at [corners] (pixels of [tile]) in the upright
  /// photo; null without corners.
  static CodeBox? boxInPhoto(
    List<({double x, double y})> corners,
    ({int x, int y, double scale}) tile,
  ) {
    if (corners.isEmpty) return null;
    final xs = corners.map((c) => c.x);
    final ys = corners.map((c) => c.y);
    final left = xs.reduce(math.min);
    final top = ys.reduce(math.min);
    return (
      left: tile.x + left / tile.scale,
      top: tile.y + top / tile.scale,
      width: (xs.reduce(math.max) - left) / tile.scale,
      height: (ys.reduce(math.max) - top) / tile.scale,
    );
  }

  /// Every distinct value in [found], in reading order: codes with a box by
  /// rows top to bottom, each row left to right; codes without one follow in
  /// the order they were found. A value found twice (overlapping tiles) keeps
  /// its first box.
  static List<String> inReadingOrder(List<FoundCode> found) {
    final boxes = <String, CodeBox>{};
    for (final f in found) {
      if (f.box != null) boxes.putIfAbsent(f.value, () => f.box!);
    }
    final unplaced = <String>[
      for (final value in {for (final f in found) f.value})
        if (!boxes.containsKey(value)) value,
    ];
    if (boxes.isEmpty) return unplaced;

    double cy(CodeBox b) => b.top + b.height / 2;
    double cx(CodeBox b) => b.left + b.width / 2;

    final byTop = boxes.entries.toList()
      ..sort((a, b) => cy(a.value).compareTo(cy(b.value)));
    final heights = [for (final e in byTop) e.value.height]..sort();
    // Codes whose centres are within half a typical code height of the
    // row's first code share its row; a slightly tilted photo stays one row.
    final tolerance = heights[heights.length ~/ 2] / 2;

    final rows = <List<MapEntry<String, CodeBox>>>[];
    for (final e in byTop) {
      if (rows.isNotEmpty &&
          (cy(e.value) - cy(rows.last.first.value)).abs() <= tolerance) {
        rows.last.add(e);
      } else {
        rows.add([e]);
      }
    }
    return [
      for (final row in rows)
        ...(row..sort((a, b) => cx(a.value).compareTo(cx(b.value))))
            .map((e) => e.key),
      ...unplaced,
    ];
  }
}
