import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/digest_service.dart';

void main() {
  group('kDigestDoctypes registry', () {
    test('has the five doctypes with the spec filters', () {
      expect(kDigestDoctypes.map((d) => d.key), [
        'purchase_order',
        'purchase_receipt',
        'delivery_note',
        'stock_entry',
        'pos_upload',
      ]);
      expect(kDigestDoctypes.map((d) => d.doctype), [
        'Purchase Order',
        'Purchase Receipt',
        'Delivery Note',
        'Stock Entry',
        'POS Upload',
      ]);
      for (final d in kDigestDoctypes.take(4)) {
        expect(d.filters, {'docstatus': 0});
      }
      expect(kDigestDoctypes.last.filters, {
        'status': ['in', ['Pending', 'In Progress']],
      });
    });
  });

  group('DigestNotificationPlan.forResult', () {
    test('ok with counts builds title + body in registry order, plurals', () {
      final plan = DigestNotificationPlan.forResult(DigestResult.ok({
        'stock_entry': 3,
        'purchase_order': 1,
        'pos_upload': 2,
      }));
      expect(plan.show, isTrue);
      expect(plan.title, 'Pending documents (6)');
      expect(plan.body,
          '1 draft Purchase Order · 3 draft Stock Entries · 2 POS Uploads to fulfil');
    });

    test('zero-count doctypes are suppressed from the body', () {
      final plan = DigestNotificationPlan.forResult(
          DigestResult.ok({'delivery_note': 0, 'purchase_receipt': 2}));
      expect(plan.title, 'Pending documents (2)');
      expect(plan.body, '2 draft Purchase Receipts');
    });

    test('all-zero → no notification', () {
      final plan = DigestNotificationPlan.forResult(
          DigestResult.ok({'purchase_order': 0}));
      expect(plan.show, isFalse);
    });

    test('empty counts → no notification', () {
      expect(DigestNotificationPlan.forResult(DigestResult.ok({})).show,
          isFalse);
    });

    test('authExpired → session-expired copy', () {
      final plan =
          DigestNotificationPlan.forResult(DigestResult.authExpired());
      expect(plan.show, isTrue);
      expect(plan.title, 'Session expired');
      expect(plan.body, 'Open Multimax to resume digests');
    });

    test('failed → silent', () {
      expect(DigestNotificationPlan.forResult(DigestResult.failed()).show,
          isFalse);
    });
  });
}
