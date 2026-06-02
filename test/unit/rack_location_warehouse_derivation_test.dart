// test/unit/rack_location_warehouse_derivation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/item_sheet/rack_location.dart';

void main() {
  group('RackLocation.warehouseName', () {
    test('derives warehouse from a standard 4-part rack code', () {
      final loc = RackLocation.tryParse('KA-WH-DXB1-101A');
      expect(loc?.warehouseName, equals('WH-DXB1 - KA'));
    });

    test('derives warehouse when company prefix differs', () {
      final loc = RackLocation.tryParse('ML-WH-DXB2-202B');
      expect(loc?.warehouseName, equals('WH-DXB2 - ML'));
    });

    test('returns null for a rack code with fewer than 4 parts', () {
      expect(RackLocation.tryParse('WH-DXB1-101A'), isNull);
    });

    test('returns null for an empty string', () {
      expect(RackLocation.tryParse(''), isNull);
    });

    test('returns null for a plain item barcode (no dashes)', () {
      expect(RackLocation.tryParse('20003609'), isNull);
    });
  });

  group('RackLocation.tryParse nullable chain', () {
    test('?.warehouseName returns the derived name for a valid rack', () {
      expect(
        RackLocation.tryParse('KA-WH-DXB1-101A')?.warehouseName,
        equals('WH-DXB1 - KA'),
      );
    });

    test('?.warehouseName returns null for a non-conforming rack string', () {
      expect(RackLocation.tryParse('BADRACK')?.warehouseName, isNull);
    });

    test('?.warehouseName returns null for an empty string', () {
      expect(RackLocation.tryParse('')?.warehouseName, isNull);
    });
  });
}
