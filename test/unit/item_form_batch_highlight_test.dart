import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';

void main() {
  group('ItemFormController.isBatchHighlighted', () {
    test('returns true when batchNo matches highlightedBatchNo', () {
      expect(ItemFormController.isBatchHighlighted('BATCH-001', 'BATCH-001'), isTrue);
    });

    test('returns false when batchNo does not match highlighted', () {
      expect(ItemFormController.isBatchHighlighted('BATCH-001', 'BATCH-002'), isFalse);
    });

    test('returns false when highlightedBatchNo is null (no scan context)', () {
      expect(ItemFormController.isBatchHighlighted('BATCH-001', null), isFalse);
    });

    test('does not highlight N/A sentinel even if null check passes', () {
      expect(ItemFormController.isBatchHighlighted('N/A', 'N/A'), isFalse);
    });
  });
}
