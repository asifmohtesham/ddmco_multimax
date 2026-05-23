import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseUploadFileResponse', () {
    test('T-1: returns null when data is null', () {
      expect(ApiProvider.parseUploadFileResponse(null), isNull);
    });

    test('T-2: returns null when message key is absent', () {
      expect(ApiProvider.parseUploadFileResponse({'other': 'data'}), isNull);
    });

    test('T-3: returns null when file_url key is absent from message', () {
      final data = <String, dynamic>{'message': {'name': 'File Name'}};
      expect(ApiProvider.parseUploadFileResponse(data), isNull);
    });

    test('T-4: returns file_url from a well-formed response', () {
      final data = <String, dynamic>{
        'message': {
          'file_url': '/files/item-image.jpg',
          'file_name': 'item-image.jpg',
        },
      };
      expect(ApiProvider.parseUploadFileResponse(data), '/files/item-image.jpg');
    });

    test('T-5: returns null when file_url value is not a String', () {
      final data = <String, dynamic>{'message': {'file_url': 42}};
      expect(ApiProvider.parseUploadFileResponse(data), isNull);
    });

    test('T-6: returns null when message is a String, not a Map', () {
      final data = <String, dynamic>{'message': 'Insufficient Permission'};
      expect(ApiProvider.parseUploadFileResponse(data), isNull);
    });
  });
}
