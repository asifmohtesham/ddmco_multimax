import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseRacksByWarehouseResponse', () {
    test('T-1: returns empty list when data is null', () {
      expect(ApiProvider.parseRacksByWarehouseResponse(null), isEmpty);
    });

    test('T-2: returns empty list when data["data"] key is absent', () {
      expect(
        ApiProvider.parseRacksByWarehouseResponse(<String, dynamic>{'other': 'value'}),
        isEmpty,
      );
    });

    test('T-3: returns empty list when data["data"] is an empty list', () {
      expect(
        ApiProvider.parseRacksByWarehouseResponse(<String, dynamic>{'data': []}),
        isEmpty,
      );
    });

    test('T-4: extracts name strings from a well-formed response', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': 'KA-WH-DXB1-101B'},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-101B', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-5: skips entries where name is null', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': null},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-6: skips entries where name is an empty string', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          {'name': ''},
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-7: skips null and non-Map entries in the data list', () {
      final data = <String, dynamic>{
        'data': [
          {'name': 'KA-WH-DXB1-101A'},
          null,
          42,
          {'name': 'KA-WH-DXB1-102A'},
        ],
      };
      expect(
        ApiProvider.parseRacksByWarehouseResponse(data),
        equals(['KA-WH-DXB1-101A', 'KA-WH-DXB1-102A']),
      );
    });

    test('T-8: returns empty list when data["data"] is not a List', () {
      final data = <String, dynamic>{'data': 'not-a-list'};
      expect(ApiProvider.parseRacksByWarehouseResponse(data), isEmpty);
    });
  });
}
