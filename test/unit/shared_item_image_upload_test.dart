import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/shared/item_sheet/shared_item_image_upload.dart';
import 'package:path/path.dart' as p;

class _UploadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final multipartBodies = <String>[];
  bool writePermission = true;
  int permissionStatus = 200;
  int updateStatus = 200;
  String? image;

  static const fileUrl = '/files/phone-photo.jpg';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == '/api/method/frappe.client.has_permission') {
      return _response({
        'message': {'has_permission': writePermission},
      }, permissionStatus);
    }
    if (options.path == '/api/method/upload_file') {
      multipartBodies.add(await latin1.decoder.bind(requestStream!).join());
      return _response({
        'message': {'file_url': fileUrl},
      });
    }
    if (options.path == '/api/resource/Item/ITEM%20%231') {
      if (options.method == 'PUT') {
        if (updateStatus != 200) return _response({}, updateStatus);
        image = (options.data as Map)['image'] as String?;
      }
      return _response({
        'data': {'image': image, 'modified': '2026-11-24 12:00:00.000000'},
      });
    }
    throw StateError('Unexpected request: ${options.path}');
  }

  static ResponseBody _response(Object body, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory directory;
  late ApiProvider api;
  late _UploadAdapter adapter;
  late SharedItemImageUpload upload;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('item_image_test_');
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
    api = ApiProvider()..setBaseUrl('https://example.invalid');
    await api.initDio();
    adapter = _UploadAdapter();
    api.dio.httpClientAdapter = adapter;
    upload = SharedItemImageUpload(api, 'ITEM #1');
  });

  tearDown(() {
    api.dio.close(force: true);
    messenger.setMockMethodCallHandler(pathChannel, null);
    directory.deleteSync(recursive: true);
  });

  test(
    'checks write permission for the specific Item and fails closed',
    () async {
      expect(await canUploadSharedItemImage(api, 'ITEM #1'), isTrue);
      expect(adapter.requests.single.queryParameters, {
        'doctype': 'Item',
        'docname': 'ITEM #1',
        'perm_type': 'write',
      });

      adapter.writePermission = false;
      expect(await canUploadSharedItemImage(api, 'ITEM #1'), isFalse);
      adapter.permissionStatus = 500;
      expect(await canUploadSharedItemImage(api, 'ITEM #1'), isFalse);
    },
  );

  test(
    'attaches the unmodified photo without optimize and sets Item.image',
    () async {
      final bytes = img.encodePng(img.Image(width: 2, height: 1));
      final photo = File(p.join(directory.path, 'phone-photo.png'))
        ..writeAsBytesSync(bytes);

      expect(await upload.save(photo.path), _UploadAdapter.fileUrl);

      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'PUT']);
      final form = adapter.requests[1].data as FormData;
      expect(Map.fromEntries(form.fields), {
        'doctype': 'Item',
        'docname': 'ITEM #1',
        'fieldname': 'image',
        'is_private': '0',
        'folder': 'Home/Attachments',
      });
      expect(form.files.single.value.filename, 'phone-photo.png');
      final body = adapter.multipartBodies.single;
      expect(body, isNot(contains('name="optimize"')));
      expect(body, contains(latin1.decode(bytes)));
      expect(adapter.requests.last.data, {
        'image': _UploadAdapter.fileUrl,
        'modified': '2026-11-24 12:00:00.000000',
      });
    },
  );

  test(
    'removes JPEG EXIF without re-encoding and leaves the source in place',
    () async {
      final image = img.Image(width: 2, height: 1);
      final expected = img.encodeJpg(image);
      image.exif.imageIfd.orientation = 1;
      image.exif.imageIfd[0x010f] = img.IfdValueAscii('Camera maker');
      final bytes = img.encodeJpg(image);
      final photo = File(p.join(directory.path, 'phone-photo.jpg'))
        ..writeAsBytesSync(bytes);

      await upload.save(photo.path);

      expect(bytes, isNot(orderedEquals(expected)));
      expect(adapter.multipartBodies.single, contains(latin1.decode(expected)));
      expect(photo.readAsBytesSync(), bytes);
    },
  );

  test('preserves the bytes when the JPEG uses EXIF orientation', () async {
    final image = img.Image(width: 2, height: 1);
    image.exif.imageIfd.orientation = 6;
    final bytes = img.encodeJpg(image);
    final photo = File(p.join(directory.path, 'phone-photo.jpg'))
      ..writeAsBytesSync(bytes);

    await upload.save(photo.path);

    expect(adapter.multipartBodies.single, contains(latin1.decode(bytes)));
  });

  test(
    'retries the Item update without uploading the attachment twice',
    () async {
      final photo = File(p.join(directory.path, 'phone-photo.png'))
        ..writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 1)));
      adapter.updateStatus = 500;
      await expectLater(upload.save(photo.path), throwsA(isA<DioException>()));
      expect(upload.hasAttachment, isTrue);

      adapter.updateStatus = 200;
      expect(await upload.save(photo.path), _UploadAdapter.fileUrl);
      expect(adapter.requests.map((r) => r.method), [
        'GET',
        'POST',
        'PUT',
        'GET',
        'PUT',
      ]);
      expect(adapter.multipartBodies, hasLength(1));
    },
  );

  test('avoids upload if an image was added since the sheet opened', () async {
    adapter.image = '/files/existing.jpg';

    await expectLater(
      upload.save('unused-photo.jpg'),
      throwsA(isA<ItemAlreadyHasImage>()),
    );
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.multipartBodies, isEmpty);
  });
}
