import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Resolves a scanned item code (and optional batch) to a [DeliveryNoteItem].
///
/// Extracted from [PackingSlipFormController._findItemInDN] so the matching
/// rules are unit-testable without GetX scaffolding.
///
/// The same item code can appear on multiple DN rows — one per invoice
/// serial. Among the code/batch matches, the first row whose [remainingQty]
/// is still positive wins, so repeated scans advance through the invoice
/// serials as each row fills up. When every match is exhausted the first
/// match is returned (not null) so the caller surfaces the existing
/// fully-packed sheet flow rather than a misleading "not found" error.
DeliveryNoteItem? findScannedDnItem({
  required List<DeliveryNoteItem> items,
  required String code,
  required String? batch,
  required double Function(DeliveryNoteItem) remainingQty,
}) {
  final matches = items.where((item) {
    final codeMatch = item.itemCode == code;
    final batchMatch = (batch == null) || (item.batchNo == batch);
    return codeMatch && batchMatch;
  }).toList();

  if (matches.isEmpty) return null;
  return matches.firstWhereOrNull((item) => remainingQty(item) > 0) ??
      matches.first;
}
