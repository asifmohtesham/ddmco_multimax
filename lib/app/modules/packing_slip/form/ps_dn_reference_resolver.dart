import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Validity of a Packing Slip's Delivery Note Item references, as it relates
/// to ERPNext's `validate_items` submit gate.
///
/// * [checking]   – the linked Delivery Note is not loaded yet; do not assert.
/// * [allLinked]  – every slip row resolves to a valid DN Item row name.
/// * [hasUnlinked]– at least one slip row's `dn_detail` is empty or stale and
///                  would trigger "missing a valid Delivery Note Item reference".
enum DnRefStatus { checking, allLinked, hasUnlinked }

/// Names of DN items that are valid link targets (non-empty `name`).
Set<String> validDnItemNames(List<DeliveryNoteItem> dnItems) => {
      for (final d in dnItems)
        if (d.name != null && d.name!.isNotEmpty) d.name!,
    };

/// True when [item]'s `dn_detail` points at a current DN Item row.
bool isSlipItemLinked(PackingSlipItem item, Set<String> validNames) =>
    item.dnDetail.isNotEmpty && validNames.contains(item.dnDetail);

/// Pure status decision used by the Items-tab banner.
DnRefStatus computeDnRefStatus({
  required List<PackingSlipItem> items,
  required Set<String> validNames,
  required bool dnLoaded,
}) {
  if (!dnLoaded) return DnRefStatus.checking;
  final hasOrphan = items.any((i) => !isSlipItemLinked(i, validNames));
  return hasOrphan ? DnRefStatus.hasUnlinked : DnRefStatus.allLinked;
}

/// Re-matches orphaned slip rows to current DN Item rows.
///
/// A row is an orphan when its `dn_detail` is empty or absent from the current
/// DN. For each orphan, candidate DN rows must share `itemCode`, the invoice
/// serial (`customInvoiceSerialNumber ?? '0'` on both sides), and — when the
/// slip row carries a non-empty batch — `batchNo`.
///
/// Among candidates, one with [remainingQty] > 0 is preferred (so packed qty is
/// attributed to a DN line that still has capacity, mirroring `findScannedDnItem`);
/// otherwise the first candidate is used. When [remainingQty] is null the first
/// candidate is always used.
///
/// Returns the patched item list plus counts: [fixed] rows were re-linked,
/// [unresolved] rows had no candidate and were left untouched.
({List<PackingSlipItem> items, int fixed, int unresolved}) resolveDnReferences({
  required List<PackingSlipItem> slipItems,
  required List<DeliveryNoteItem> dnItems,
  double Function(DeliveryNoteItem)? remainingQty,
}) {
  final validNames = validDnItemNames(dnItems);
  var fixed = 0;
  var unresolved = 0;

  final patched = slipItems.map((item) {
    if (isSlipItemLinked(item, validNames)) return item;

    final itemSerial = item.customInvoiceSerialNumber ?? '0';
    final candidates = dnItems.where((d) {
      if (d.name == null || d.name!.isEmpty) return false;
      if (d.itemCode != item.itemCode) return false;
      if ((d.customInvoiceSerialNumber ?? '0') != itemSerial) return false;
      if (item.batchNo.isNotEmpty && d.batchNo != item.batchNo) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) {
      unresolved++;
      return item;
    }

    final chosen = remainingQty == null
        ? candidates.first
        : (candidates.firstWhereOrNull((d) => remainingQty(d) > 0) ??
            candidates.first);

    fixed++;
    return item.copyWith(dnDetail: chosen.name!);
  }).toList();

  return (items: patched, fixed: fixed, unresolved: unresolved);
}
