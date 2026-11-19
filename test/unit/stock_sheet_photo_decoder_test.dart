import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';

// Four items' EAN-8s (valid check digits), a batch QR of the first, and an
// EAN-13 that is no item's code.
const _a = '10039991';
const _b = '10039908';
const _c = '10040010';
const _d = '10039915';
const _aBatch = '10039991-4CPIWR';
const _ean13 = '4006381333931';

/// Stands in for ML Kit: answers by the file's name and keeps the calls.
class _FakeAnalyser {
  final calls = <String>[];

  /// What files hold: the first entry whose test passes on the file name
  /// answers; a file no entry matches holds nothing.
  final holds = <(bool Function(String name), List<AnalysedCode>)>[];

  /// Files whose reading throws this.
  final throws = <(bool Function(String name), Object)>[];

  Future<List<AnalysedCode>> call(String path) async {
    calls.add(path);
    final name = path.split('/').last;
    for (final (matches, error) in throws) {
      if (matches(name)) throw error;
    }
    for (final (matches, codes) in holds) {
      if (matches(name)) return codes;
    }
    return const [];
  }

  List<String> get names => [for (final c in calls) c.split('/').last];
  Iterable<String> get tiles =>
      names.where((n) => n.startsWith('stock_sheet_tile_'));
  Iterable<String> get retries =>
      names.where((n) => n.startsWith('stock_sheet_retry_'));
}

bool Function(String) _named(String name) =>
    (n) => n == name;

/// The tile with this index and copy ('s' smooth, 'n' sharp, '' as it is).
bool Function(String) _tile(int index, String copy) =>
    (n) => n.startsWith('stock_sheet_tile_') && n.endsWith('_$index$copy.png');

AnalysedCode _plain(String value) => (value: value, corners: const []);

/// A code 20 x 8 px at ([left], [top]) in the photo, as its corners in a
/// tile whose corner is at ([tileX], [tileY]) and which is enlarged 4x.
AnalysedCode _at(String value, int left, int top, int tileX, int tileY) {
  final l = (left - tileX) * 4.0;
  final t = (top - tileY) * 4.0;
  return (
    value: value,
    corners: [
      (x: l, y: t),
      (x: l + 80, y: t),
      (x: l + 80, y: t + 32),
      (x: l, y: t + 32),
    ],
  );
}

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

    test('holds exactly the pixels of the image package\'s cubic resize', () {
      final source = img.Image(width: 31, height: 17);
      for (final p in source) {
        final v = (p.x * 37 + p.y * 91) % 3 == 0 ? 0 : 255;
        p.setRgb(v, v, v);
      }
      final copy = MlKitPhotoDecoder.upscaledCopy(
        Uint8List.fromList(img.encodePng(source)),
      );
      final expected = img.copyResize(
        img.grayscale(source),
        width: 62,
        height: 34,
        interpolation: img.Interpolation.cubic,
      );
      expect(img.decodePng(copy!)!.toUint8List(), expected.toUint8List());
    });
  });

  group('decode', () {
    late Directory photos;
    late Directory temp;
    late _FakeAnalyser analyser;
    late MlKitPhotoDecoder decoder;

    setUp(() async {
      photos = await Directory.systemTemp.createTemp('decoder_photos');
      temp = await Directory.systemTemp.createTemp('decoder_temp');
      analyser = _FakeAnalyser();
      decoder = MlKitPhotoDecoder(
        analyser: analyser.call,
        temporaryPath: () async => temp.path,
      );
    });

    tearDown(() async {
      await decoder.dispose();
      await photos.delete(recursive: true);
      await temp.delete(recursive: true);
    });

    /// A blank [width] x [height] photo on disk. At 200 x 100 its nine tiles
    /// are 120 x 60, at x 0, 40, 80 and y 0, 20, 40, each enlarged 4x and
    /// written smooth and sharp: 18 files.
    String photo({int width = 200, int height = 100}) {
      final file = File('${photos.path}/photo.png')
        ..writeAsBytesSync(
          img.encodePng(img.Image(width: width, height: height)),
        );
      return file.path;
    }

    test('readWhole reads the photo once and nothing else', () async {
      analyser.holds.add((_named('photo.png'), [_plain(_a)]));
      expect(await decoder.readWhole(photo()), [_a]);
      expect(analyser.calls, hasLength(1));
    });

    test('needsZoom: no item or several, never exactly one', () {
      expect(PhotoDecoder.needsZoom(const []), isTrue);
      expect(PhotoDecoder.needsZoom(const [_ean13]), isTrue);
      expect(PhotoDecoder.needsZoom(const [_a, _aBatch]), isFalse);
      expect(PhotoDecoder.needsZoom(const [_a, _b]), isTrue);
    });

    test('zoomIn gives what decode gave for the same photo', () async {
      analyser.holds.add((_tile(8, 'n'), [_at(_a, 150, 85, 80, 40)]));
      final path = photo();
      expect(await decoder.zoomIn(path, whole: const []), [_a]);
      expect(analyser.tiles, hasLength(18));
    });

    test(
      'zoomIn stops before the next tile, gives null and leaves no file',
      () async {
        var reads = 0;
        final result = await decoder.zoomIn(
          photo(),
          whole: const [],
          // Asked once after writing, then before each read.
          stopped: () => ++reads > 3,
        );
        expect(result, isNull);
        expect(analyser.tiles.length, lessThan(18));
        expect(analyser.retries, isEmpty);
        expect(temp.listSync(), isEmpty);
      },
    );

    test('zoomIn stopped while the tiles were being written reads none', () async {
      expect(
        await decoder.zoomIn(photo(), whole: const [], stopped: () => true),
        isNull,
      );
      expect(analyser.tiles, isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('a first pass that finds nothing is followed by the tiles: one '
        'small label is read from the tile that holds it', () async {
      // The wallet-card case: the label sits bottom right, too small in the
      // whole photo, readable in the last tile.
      analyser.holds.add((_tile(8, 'n'), [_at(_a, 150, 85, 80, 40)]));

      expect(await decoder.decode(photo()), [_a]);
      expect(analyser.names.first, 'photo.png');
      expect(analyser.tiles, hasLength(18));
      // The tiles answered: the 2x copy of the whole photo is not made.
      expect(analyser.retries, isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('what the tiles find comes once each, in reading order', () async {
      // Two rows of two labels; overlapping tiles and both copies of a tile
      // find the same label, and the tiles meet them out of order.
      analyser.holds.addAll([
        (_tile(2, 's'), [_at(_c, 150, 45, 80, 0)]),
        (_tile(6, 'n'), [_at(_d, 45, 85, 0, 40), _at(_a, 45, 45, 0, 40)]),
        (_tile(7, 's'), [_at(_a, 45, 45, 40, 40), _at(_d, 45, 85, 40, 40)]),
        (_tile(8, 's'), [_at(_b, 150, 85, 80, 40)]),
        (_tile(8, 'n'), [_at(_b, 150, 85, 80, 40)]),
      ]);

      expect(await decoder.decode(photo()), [_a, _c, _d, _b]);
    });

    test('another kind of code in the first pass still leads to the tiles, '
        'and follows what they find', () async {
      analyser.holds.addAll([
        (_named('photo.png'), [_plain(_ean13)]),
        (_tile(4, 's'), [_at(_a, 90, 40, 40, 20)]),
      ]);

      expect(await decoder.decode(photo()), [_a, _ean13]);
      expect(analyser.retries, isEmpty);
    });

    test(
      'tiles that find nothing leave a small photo its 2x copy, last',
      () async {
        analyser.holds.add((
          (n) => n.startsWith('stock_sheet_retry_'),
          [_plain(_a)],
        ));

        expect(await decoder.decode(photo()), [_a]);
        expect(analyser.tiles, hasLength(18));
        expect(analyser.retries, hasLength(1));
        expect(analyser.names.last, startsWith('stock_sheet_retry_'));
        expect(temp.listSync(), isEmpty);
      },
    );

    test('a photo of 2000 px or more gets tiles but no 2x copy', () async {
      // 1200 x 24 tiles: large enough, so written once and not enlarged.
      expect(await decoder.decode(photo(width: 2000, height: 40)), isEmpty);
      expect(analyser.tiles, hasLength(9));
      expect(analyser.retries, isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('nothing found anywhere gives what the first pass gave', () async {
      analyser.holds.add((_named('photo.png'), [_plain(_ean13)]));

      expect(await decoder.decode(photo()), [_ean13]);
      expect(analyser.tiles, hasLength(18));
      expect(analyser.retries, hasLength(1));
      expect(temp.listSync(), isEmpty);
    });

    test(
      'one item in the first pass is the answer: nothing is read again',
      () async {
        analyser.holds.add((
          _named('photo.png'),
          [_plain(_a), _plain(_aBatch)],
        ));

        expect(await decoder.decode(photo()), [_a, _aBatch]);
        expect(analyser.calls, hasLength(1));
        expect(temp.listSync(), isEmpty);
      },
    );

    test('two or more items in the first pass are read again in tiles, '
        'without the 2x copy', () async {
      analyser.holds.addAll([
        (_named('photo.png'), [_plain(_b), _plain(_a)]),
        (_tile(0, 's'), [_at(_a, 20, 10, 0, 0), _at(_c, 60, 10, 0, 0)]),
      ]);

      // Placed codes in reading order, then the one only the first pass saw.
      expect(await decoder.decode(photo()), [_a, _c, _b]);
      expect(analyser.tiles, hasLength(18));
      expect(analyser.retries, isEmpty);
    });

    test('two or more items stay as the first pass gave them when the photo '
        'cannot be cut into tiles', () async {
      final path = '${photos.path}/photo.png';
      File(path).writeAsBytesSync([1, 2, 3]);
      analyser.holds.add((_named('photo.png'), [_plain(_b), _plain(_a)]));

      expect(await decoder.decode(path), [_b, _a]);
      expect(analyser.calls, hasLength(1));
    });

    test(
      'a file that is not an image and holds nothing gives nothing',
      () async {
        final path = '${photos.path}/photo.png';
        File(path).writeAsBytesSync([1, 2, 3]);

        expect(await decoder.decode(path), isEmpty);
        expect(analyser.calls, hasLength(1));
      },
    );

    test('a tile that cannot be read is skipped; the others count', () async {
      analyser.throws.add((_tile(3, 's'), Exception('unreadable')));
      analyser.holds.add((_tile(8, 's'), [_at(_a, 150, 85, 80, 40)]));

      expect(await decoder.decode(photo()), [_a]);
      expect(analyser.tiles, hasLength(18));
      expect(temp.listSync(), isEmpty);
    });

    test('a photo the platform cannot read is null', () async {
      analyser.throws.add((_named('photo.png'), Exception('unreadable')));

      expect(await decoder.decode(photo()), isNull);
      expect(analyser.calls, hasLength(1));
    });

    test('a platform without barcode reading says so, from the first pass '
        'or from a tile', () async {
      analyser.throws.add((_tile(0, 's'), UnsupportedError('no ML Kit')));
      await expectLater(decoder.decode(photo()), throwsUnsupportedError);
      expect(temp.listSync(), isEmpty);

      analyser.throws
        ..clear()
        ..add((_named('photo.png'), UnsupportedError('no ML Kit')));
      await expectLater(decoder.decode(photo()), throwsUnsupportedError);
    });
  });
}
