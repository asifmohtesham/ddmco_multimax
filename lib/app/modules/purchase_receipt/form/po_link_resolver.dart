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

  /// Eligible rows for [PoLinkOutcome.needsPicker].
  final List<PoLinkCandidate> candidates;

  /// Every cached row for the item_code (open + closed) — what the picker shows.
  final List<PoLinkCandidate> allForItem;

  /// Human-readable reason for [PoLinkOutcome.blocked].
  final String? reason;

  const PoLinkResult._({
    required this.outcome,
    this.linked,
    this.candidates = const [],
    this.allForItem = const [],
    this.reason,
  });

  factory PoLinkResult.autoLinked(
          PoLinkCandidate row, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.autoLinked, linked: row, allForItem: all);

  factory PoLinkResult.needsPicker(
          List<PoLinkCandidate> eligible, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.needsPicker,
          candidates: eligible,
          allForItem: all);

  factory PoLinkResult.blocked(String reason, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.blocked, reason: reason, allForItem: all);
}

/// Resolves which cached Purchase Order row an item should link to.
///
/// Rules (design 2026-06-24, Section 1):
///   - Candidates = cached rows with matching item_code.
///   - Open candidates have received_qty < qty.
///   - Closed rows (received_qty >= qty) are eligible only when
///     [allowOverReceipt] is true.
///   - 1 eligible -> autoLinked; >=2 -> needsPicker; 0 -> blocked.
PoLinkResult resolvePoLinkFor(
  List<PoLinkCandidate> cached,
  String itemCode, {
  required bool allowOverReceipt,
}) {
  final all = cached.where((c) => c.item.itemCode == itemCode).toList();
  if (all.isEmpty) {
    return PoLinkResult.blocked(
      'No Purchase Order line for $itemCode on any linked Purchase Order.',
      all,
    );
  }

  final open = all.where((c) => c.isOpen).toList();
  final eligible = allowOverReceipt ? all : open;

  if (eligible.isEmpty) {
    return PoLinkResult.blocked(
      'No open Purchase Order line for $itemCode on ${all.first.poName} — '
      'enable Allow Over-Receipt to receive against a closed line.',
      all,
    );
  }
  if (eligible.length == 1) {
    return PoLinkResult.autoLinked(eligible.first, all);
  }
  return PoLinkResult.needsPicker(eligible, all);
}

/// Qty ceiling for the qty field. Over-receipt lifts the PO cap entirely.
double poQtyCeiling(double? poQty, {required bool allowOverReceipt}) {
  if (allowOverReceipt) return double.infinity;
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
