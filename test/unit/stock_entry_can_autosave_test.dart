import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

void main() {
  group('StockEntryFormController.computeCanAutoSave', () {
    // A complete Material Transfer draft with one item and both warehouses set.
    bool call({
      bool hasItems = true,
      String stockEntryType = 'Material Transfer',
      bool requiresSourceWarehouse = true,
      bool requiresTargetWarehouse = true,
      String? fromWarehouse = 'Stores - X',
      String? toWarehouse = 'WIP - X',
    }) =>
        StockEntryFormController.computeCanAutoSave(
          hasItems: hasItems,
          stockEntryType: stockEntryType,
          requiresSourceWarehouse: requiresSourceWarehouse,
          requiresTargetWarehouse: requiresTargetWarehouse,
          fromWarehouse: fromWarehouse,
          toWarehouse: toWarehouse,
        );

    test('T-1: complete Material Transfer with an item → true', () {
      expect(call(), isTrue);
    });

    test('T-2: no items → false (the reported bug)', () {
      expect(call(hasItems: false), isFalse);
    });

    test('T-3: empty stock entry type → false', () {
      expect(call(stockEntryType: ''), isFalse);
    });

    test('T-4: missing source warehouse when required → false', () {
      expect(call(fromWarehouse: null), isFalse);
      expect(call(fromWarehouse: ''), isFalse);
    });

    test('T-5: missing target warehouse when required → false', () {
      expect(call(toWarehouse: null), isFalse);
      expect(call(toWarehouse: ''), isFalse);
    });

    test('T-6: Material Issue needs only source warehouse', () {
      bool issue({String? from, String? to}) => call(
            stockEntryType: 'Material Issue',
            requiresSourceWarehouse: true,
            requiresTargetWarehouse: false,
            fromWarehouse: from,
            toWarehouse: to,
          );
      expect(issue(from: 'Stores - X', to: null), isTrue);
      expect(issue(from: null, to: null), isFalse);
    });

    test('T-7: Material Receipt needs only target warehouse', () {
      bool receipt({String? from, String? to}) => call(
            stockEntryType: 'Material Receipt',
            requiresSourceWarehouse: false,
            requiresTargetWarehouse: true,
            fromWarehouse: from,
            toWarehouse: to,
          );
      expect(receipt(from: null, to: 'Stores - X'), isTrue);
      expect(receipt(from: null, to: null), isFalse);
    });
  });
}
