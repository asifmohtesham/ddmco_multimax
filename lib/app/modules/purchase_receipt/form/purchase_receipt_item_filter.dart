import 'package:multimax/app/data/models/purchase_receipt_model.dart';

/// Status filter applied to the rows shown on the Purchase Receipt form's
/// Items tab. "Completed" means fully received against the PO line; "Pending"
/// means a row is yet to be fully received (this is what the user triages for);
/// "Link broken" means an orphaned PO reference whose line can no longer be
/// resolved and needs repair. [all] applies no filtering.
enum ReceiptItemFilter { all, pending, completed, linkBroken }

extension ReceiptItemFilterLabel on ReceiptItemFilter {
  String get label {
    switch (this) {
      case ReceiptItemFilter.all:
        return 'All';
      case ReceiptItemFilter.pending:
        return 'Pending';
      case ReceiptItemFilter.completed:
        return 'Completed';
      case ReceiptItemFilter.linkBroken:
        return 'Link broken';
    }
  }
}

/// Whether [item] passes [filter].
///
/// Completeness is read from [PurchaseReceiptItem.isFullyReceived], the same
/// predicate that drives the green "Fully received" progress bar, so the chip
/// counts and the per-row indicator always agree. Orphaned rows
/// ([PurchaseReceiptItem.isPoLinkBroken]) are excluded from both Pending and
/// Completed — they are a distinct state, never silently counted as "pending".
bool matchesReceiptItemFilter(
  PurchaseReceiptItem item,
  ReceiptItemFilter filter,
) {
  switch (filter) {
    case ReceiptItemFilter.all:
      return true;
    case ReceiptItemFilter.linkBroken:
      return item.isPoLinkBroken;
    case ReceiptItemFilter.completed:
      return !item.isPoLinkBroken && item.isFullyReceived;
    case ReceiptItemFilter.pending:
      return !item.isPoLinkBroken && !item.isFullyReceived;
  }
}

/// Returns the subset of [items] matching [filter], preserving order.
List<PurchaseReceiptItem> filterReceiptItems(
  List<PurchaseReceiptItem> items,
  ReceiptItemFilter filter,
) {
  if (filter == ReceiptItemFilter.all) return List.of(items);
  return items.where((i) => matchesReceiptItemFilter(i, filter)).toList();
}

/// Count of [items] matching [filter] — used for the chip badges.
int countReceiptItems(
  List<PurchaseReceiptItem> items,
  ReceiptItemFilter filter,
) {
  if (filter == ReceiptItemFilter.all) return items.length;
  return items.where((i) => matchesReceiptItemFilter(i, filter)).length;
}
