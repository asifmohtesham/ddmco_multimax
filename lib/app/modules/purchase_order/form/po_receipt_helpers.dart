import 'package:multimax/app/data/models/purchase_order_model.dart';

/// True when at least one PO line still has quantity left to receive
/// (received_qty < qty). Drives the "Create Purchase Receipt" action's
/// visibility — the action is hidden once the PO is fully received.
bool hasOpenReceiptQty(List<PurchaseOrderItem> items) =>
    items.any((i) => i.receivedQty < i.qty);

/// A draft Purchase Receipt linked to a Purchase Order, summarised for the
/// resume-or-create sheet.
class DraftReceiptSummary {
  final String name;
  final String postingDate;
  const DraftReceiptSummary({required this.name, required this.postingDate});
}

/// Distinct, order-preserving `parent` names from a `Purchase Receipt Item`
/// child-list response (`{"data": [{"parent": "..."}]}`). Tolerant of null,
/// non-Map payloads, and missing/blank parents.
List<String> parseDraftReceiptParents(dynamic responseData) {
  if (responseData is! Map) return const [];
  final rows = responseData['data'];
  if (rows is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final p = r['parent'];
    if (p is! String || p.isEmpty) continue;
    if (seen.add(p)) out.add(p);
  }
  return out;
}
