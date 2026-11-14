// test/unit/rack_warehouse_lookup_response_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseRackWarehouseResponse', () {
    test('T-1: extracts warehouse from a well-formed Rack doc response', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A', 'warehouse': 'WH-DXB1 - KA'},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data),
          equals('WH-DXB1 - KA'));
    });

    test('T-2: returns null when warehouse field is missing', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A'},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });

    test('T-3: returns null when warehouse field is empty', () {
      final data = {
        'data': {'name': 'KA-WH-DXB1-101A', 'warehouse': ''},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });

    test('T-4: returns null on null input', () {
      expect(ApiProvider.parseRackWarehouseResponse(null), isNull);
    });

    test('T-5: returns null when data key is not a Map', () {
      expect(ApiProvider.parseRackWarehouseResponse({'data': []}), isNull);
      expect(ApiProvider.parseRackWarehouseResponse({'data': 'x'}), isNull);
    });

    test('T-6: returns null when warehouse is not a String', () {
      final data = {
        'data': {'warehouse': 42},
      };
      expect(ApiProvider.parseRackWarehouseResponse(data), isNull);
    });
  });

  group('RackWarehouseLookup constructors', () {
    test('T-7: found(null) is distinguishable from notFound', () {
      const found    = RackWarehouseLookup.found(null);
      const notFound = RackWarehouseLookup.notFound();
      expect(found.status, equals(RackLookupStatus.found));
      expect(found.warehouse, isNull);
      expect(notFound.status, equals(RackLookupStatus.notFound));
      expect(notFound.warehouse, isNull);
    });
  });
}
