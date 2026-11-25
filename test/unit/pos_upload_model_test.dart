import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';

void main() {
  group('PosUpload.fromJson', () {
    test('reads all seven canonical statuses', () {
      const statuses = [
        'Pending',
        'In Progress',
        'To Deliver',
        'Out for Delivery',
        'Delivered',
        'Completed',
        'Cancelled',
      ];
      expect(PosUpload.statusOptions, statuses);
      for (final status in statuses) {
        expect(PosUpload.fromJson({'status': status}).status, status);
      }
    });

    test('defaults missing, null and blank status to Pending', () {
      expect(PosUpload.fromJson({}).status, 'Pending');
      for (final status in [null, '', ' \t']) {
        expect(PosUpload.fromJson({'status': status}).status, 'Pending');
      }
    });

    test('preserves legacy and unknown status labels verbatim', () {
      for (final status in ['Draft', 'Submitted', '  Awaiting review ']) {
        expect(PosUpload.fromJson({'status': status}).status, status);
      }
    });

    test('reads optional return reasons and preserves unrecognized labels', () {
      expect(PosUpload.fromJson({}).returnReason, isNull);
      for (final reason in [null, '', '  ']) {
        expect(
          PosUpload.fromJson({'custom_return_reason': reason}).returnReason,
          isNull,
        );
      }
      for (final reason in ['Late', 'Rejected', 'Other', ' New reason ']) {
        expect(
          PosUpload.fromJson({'custom_return_reason': reason}).returnReason,
          reason,
        );
      }
    });
  });

  group('PosUploadItem.fromJson', () {
    test('parses ref_code alongside the existing fields', () {
      final item = PosUploadItem.fromJson({
        'idx': 3,
        'ref_code': 'CUST-REF-9',
        'item_name': 'Strap 20mm',
        'qty': 4,
        'rate': 1.5,
        'amount': 6.0,
      });
      expect(item.idx, 3);
      expect(item.refCode, 'CUST-REF-9');
      expect(item.itemName, 'Strap 20mm');
      expect(item.quantity, 4);
    });

    test('parses uom, the unit the rate is quoted in', () {
      final item = PosUploadItem.fromJson({
        'idx': 1,
        'item_name': 'WALLETS GOAT HQ',
        'rate': 220,
        'uom': 'Doz',
        'quantity': 120,
        'amount': 2200,
      });
      expect(item.uom, 'Doz');
    });

    test('missing or null uom defaults to empty string', () {
      expect(PosUploadItem.fromJson({'idx': 1, 'item_name': 'X'}).uom, '');
      expect(
        PosUploadItem.fromJson({'idx': 1, 'item_name': 'X', 'uom': null}).uom,
        '',
      );
    });

    test('missing ref_code defaults to empty string', () {
      final item = PosUploadItem.fromJson({'idx': 1, 'item_name': 'X'});
      expect(item.refCode, '');
    });
  });
}
