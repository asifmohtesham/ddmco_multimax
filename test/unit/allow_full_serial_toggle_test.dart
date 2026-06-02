import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';

void main() {
  group('SerialDropdownItem.isFull', () {
    test('is true when remaining <= 0 and qty is finite', () {
      const item = SerialDropdownItem(serial: '1', qty: 10, remaining: 0);
      expect(item.isFull, isTrue);
    });

    test('is true when remaining is negative (over-allocation)', () {
      const item = SerialDropdownItem(serial: '1', qty: 10, remaining: -1);
      expect(item.isFull, isTrue);
    });

    test('is false when remaining > 0', () {
      const item = SerialDropdownItem(serial: '1', qty: 10, remaining: 3);
      expect(item.isFull, isFalse);
    });

    test('is false when qty is null', () {
      const item = SerialDropdownItem(serial: '1', qty: null, remaining: 0);
      expect(item.isFull, isFalse);
    });

    test('is false when qty is infinity', () {
      const item = SerialDropdownItem(
          serial: '1', qty: double.infinity, remaining: 0);
      expect(item.isFull, isFalse);
    });
  });
}
