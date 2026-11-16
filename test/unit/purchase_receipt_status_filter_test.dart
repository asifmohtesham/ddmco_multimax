import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_status_filter.dart';

void main() {
  group('purchaseReceiptQueryFilters', () {
    test('Submitted is docstatus 1, not a status value', () {
      // Purchase Receipt has no "Submitted" status: submitted receipts read
      // To Bill, Partly Billed, Completed, Return, Return Issued or Closed.
      expect(purchaseReceiptQueryFilters({'status': 'Submitted'}),
          {'docstatus': 1});
    });

    test('Draft and Cancelled are docstatus 0 and 2', () {
      expect(
          purchaseReceiptQueryFilters({'status': 'Draft'}), {'docstatus': 0});
      expect(purchaseReceiptQueryFilters({'status': 'Cancelled'}),
          {'docstatus': 2});
    });

    test('Completed stays a status filter', () {
      expect(purchaseReceiptQueryFilters({'status': 'Completed'}),
          {'status': 'Completed'});
    });

    test('a real status value from elsewhere passes through', () {
      expect(purchaseReceiptQueryFilters({'status': 'Partly Billed'}),
          {'status': 'Partly Billed'});
    });

    test('a non-string status filter passes through', () {
      final inFilter = {
        'status': ['in', ['To Bill', 'Partly Billed']],
      };
      expect(purchaseReceiptQueryFilters(inFilter), inFilter);
    });

    test('other filters are kept and the input is not changed', () {
      final active = <String, dynamic>{
        'status': 'Submitted',
        'supplier': 'SUP-0001',
      };
      expect(purchaseReceiptQueryFilters(active), {
        'docstatus': 1,
        'supplier': 'SUP-0001',
      });
      expect(active['status'], 'Submitted');
      expect(active.containsKey('docstatus'), isFalse);
    });

    test('no status filter leaves the filters as they are', () {
      expect(purchaseReceiptQueryFilters({'supplier': 'SUP-0001'}),
          {'supplier': 'SUP-0001'});
      expect(purchaseReceiptQueryFilters({}), isEmpty);
    });

    test('every choice the sheet offers maps to a valid query', () {
      // Upstream purchase_receipt.json, version-15 and v16.55.0 alike.
      const validStatuses = {
        'Draft', 'Partly Billed', 'To Bill', 'Completed', 'Return',
        'Return Issued', 'Cancelled', 'Closed',
      };
      for (final choice in purchaseReceiptStatusChoices) {
        final q = purchaseReceiptQueryFilters({'status': choice});
        if (q.containsKey('status')) {
          expect(validStatuses, contains(q['status']),
              reason: '"$choice" must be a real Purchase Receipt status');
        } else {
          expect(q.keys.single, 'docstatus',
              reason: '"$choice" must map to docstatus');
        }
      }
    });

    test("the dashboard's actionable filters still query drafts", () {
      // The dashboard opens the list with {'status': 'Draft', 'owner': ...};
      // the label is kept for the chip and sent as docstatus 0.
      final args = actionableFiltersFor(
          'Purchase Receipt', ActionableScope.mine, 'a@b.com');
      expect(args, {'status': 'Draft', 'owner': 'a@b.com'});
      expect(purchaseReceiptStatusChoices, contains(args['status']));
      expect(purchaseReceiptQueryFilters(args),
          {'docstatus': 0, 'owner': 'a@b.com'});
    });
  });
}
