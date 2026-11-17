import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_status_filter.dart';

void main() {
  group('deliveryNoteQueryFilters', () {
    test('Submitted is docstatus 1, not a status value', () {
      // Delivery Note has no "Submitted" status: submitted notes read
      // To Bill, Partially Billed, Completed, Return, Return Issued or Closed.
      expect(deliveryNoteQueryFilters({'status': 'Submitted'}),
          {'docstatus': 1});
    });

    test('Draft and Cancelled are docstatus 0 and 2', () {
      expect(deliveryNoteQueryFilters({'status': 'Draft'}), {'docstatus': 0});
      expect(deliveryNoteQueryFilters({'status': 'Cancelled'}),
          {'docstatus': 2});
    });

    test('Return is is_return 1, so billed and draft returns are included', () {
      expect(deliveryNoteQueryFilters({'status': 'Return'}), {'is_return': 1});
    });

    test('Completed stays a status filter', () {
      expect(deliveryNoteQueryFilters({'status': 'Completed'}),
          {'status': 'Completed'});
    });

    test('a real status value from elsewhere passes through', () {
      expect(deliveryNoteQueryFilters({'status': 'To Bill'}),
          {'status': 'To Bill'});
    });

    test('other filters are kept and the input is not changed', () {
      final active = <String, dynamic>{
        'status': 'Submitted',
        'customer': 'CUST-0001',
        'po_no': ['like', '%PO-1%'],
      };
      expect(deliveryNoteQueryFilters(active), {
        'docstatus': 1,
        'customer': 'CUST-0001',
        'po_no': ['like', '%PO-1%'],
      });
      expect(active['status'], 'Submitted');
      expect(active.containsKey('docstatus'), isFalse);
    });

    test('no status filter leaves the filters as they are', () {
      expect(deliveryNoteQueryFilters({'owner': 'a@b.com'}),
          {'owner': 'a@b.com'});
      expect(deliveryNoteQueryFilters({}), isEmpty);
    });

    test('every choice the sheet offers maps to a valid query', () {
      const validStatuses = {
        'Draft', 'To Bill', 'Partially Billed', 'Completed', 'Return',
        'Return Issued', 'Cancelled', 'Closed',
      };
      for (final choice in deliveryNoteStatusChoices) {
        final q = deliveryNoteQueryFilters({'status': choice});
        if (q.containsKey('status')) {
          expect(validStatuses, contains(q['status']),
              reason: '"$choice" must be a real Delivery Note status');
        } else {
          expect(q.keys.single, anyOf('docstatus', 'is_return'),
              reason: '"$choice" must map to docstatus or is_return');
        }
      }
    });
  });
}
