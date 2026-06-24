import 'package:multimax/app/data/models/purchase_order_model.dart';

/// One cached Purchase Order row paired with its source PO name.
class PoLinkCandidate {
  final String poName;
  final PurchaseOrderItem item;
  const PoLinkCandidate(this.poName, this.item);

  /// A row still has open quantity to receive against.
  bool get isOpen => item.receivedQty < item.qty;
}

enum PoLinkOutcome { autoLinked, needsPicker, blocked }

/// Result of resolving a Purchase Order Item reference for a scanned item.
class PoLinkResult {
  final PoLinkOutcome outcome;

  /// Set for [PoLinkOutcome.autoLinked].
  final PoLinkCandidate? linked;

  /// The open rows to choose from for [PoLinkOutcome.needsPicker].
  final List<PoLinkCandidate> candidates;

  /// Human-readable reason for [PoLinkOutcome.blocked].
  final String? reason;

  const PoLinkResult._({
    required this.outcome,
    this.linked,
    this.candidates = const [],
    this.reason,
  });

  factory PoLinkResult.autoLinked(PoLinkCandidate row) =>
      PoLinkResult._(outcome: PoLinkOutcome.autoLinked, linked: row);

  factory PoLinkResult.needsPicker(List<PoLinkCandidate> openRows) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.needsPicker, candidates: openRows);

  factory PoLinkResult.blocked(String reason) =>
      PoLinkResult._(outcome: PoLinkOutcome.blocked, reason: reason);
}

/// Resolves which cached Purchase Order row an item should link to.
///
/// Open-rows-only by design (no over-receipt). Receiving above ordered, or
/// against a fully-received line, is a policy decision ERPNext owns via its
/// `over_delivery_receipt_allowance` tolerance — the app never facilitates it.
///
/// Rules:
///   - Candidates = cached rows with matching item_code.
///   - Eligible = OPEN candidates only (received_qty < qty).
///   - 1 open -> autoLinked; >=2 open -> needsPicker; 0 open -> blocked.
PoLinkResult resolvePoLinkFor(
  List<PoLinkCandidate> cached,
  String itemCode,
) {
  final all = cached.where((c) => c.item.itemCode == itemCode).toList();
  if (all.isEmpty) {
    return PoLinkResult.blocked(
      'No Purchase Order line for $itemCode on any linked Purchase Order.',
    );
  }

  final open = all.where((c) => c.isOpen).toList();

  if (open.isEmpty) {
    return PoLinkResult.blocked(
      'No open Purchase Order line for $itemCode on ${all.first.poName} — '
      'the line is fully received. Resolve on the Purchase Order before '
      'receiving.',
    );
  }
  if (open.length == 1) {
    return PoLinkResult.autoLinked(open.first);
  }
  return PoLinkResult.needsPicker(open);
}

/// Qty ceiling for the qty field: the PO ordered qty, or no ceiling when the
/// item carries no PO qty. Qty above ordered is never permitted in-app.
double poQtyCeiling(double? poQty) {
  if (poQty != null && poQty > 0) return poQty;
  return double.infinity;
}

/// Extracts offending PO Item row names from an ERPNext 417 exception string.
/// Matches `Invalid reference Purchase Order Item <name>` (name is a Frappe
/// hash: word chars and dashes), stopping cleanly before the closing JSON `"`.
Set<String> parseInvalidPoItemRefs(String message) {
  final re = RegExp(r'Invalid reference Purchase Order Item ([\w-]+)');
  return re.allMatches(message).map((m) => m.group(1)!).toSet();
}

/// Thrown from item-sheet submit when the user cancels the link picker or the
/// item is blocked — keeps the sheet open (submitWithFeedback returns false).
class PoLinkAbortedException implements Exception {
  const PoLinkAbortedException();
  @override
  String toString() => 'PoLinkAbortedException';
}
