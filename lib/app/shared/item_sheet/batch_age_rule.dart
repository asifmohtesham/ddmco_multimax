/// Oldest stock first — the pure rule.
///
/// A batch may not be picked while an older batch of the same item still has
/// stock. This file holds only the decision; fetching the inputs lives in
/// `batch_age_provider.dart` and the orchestration in
/// `batch_age_checker.dart`. See `docs/batch_age_validation.md`.
library;

/// Only warehouses whose name starts with this prefix take part: picks from
/// any other warehouse are not checked, and stock held elsewhere never blocks.
const String kBatchAgeWarehousePrefix = 'WH-';

/// Balances at or below this are treated as nothing left.
const double kBatchAgeQtyEpsilon = 1e-6;

/// Whether the rule covers [warehouse].
bool batchAgeRuleApplies(String? warehouse) =>
    warehouse != null &&
    warehouse.trim().toUpperCase().startsWith(kBatchAgeWarehousePrefix);

/// Reads the date part of a Frappe date (`2026-11-18`) or datetime
/// (`2026-11-18 09:14:11.098488`). The server's wall-clock day is kept as
/// written: no time-zone conversion, so a batch never changes day on a phone
/// in another zone.
DateTime? parseBatchAgeDate(Object? raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})')
      .firstMatch(raw?.toString().trim() ?? '');
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// The day a batch counts from, and where that day came from.
class BatchAge {
  const BatchAge(this.date, {required this.fromReceipt});

  /// Day precision; time of day is always midnight.
  final DateTime date;

  /// True when [date] is the batch's earliest Purchase Receipt; false when the
  /// batch was never on one and the Batch record's own date is used instead.
  final bool fromReceipt;

  @override
  String toString() => 'BatchAge($date, fromReceipt: $fromReceipt)';
}

/// Earliest submitted Purchase Receipt wins; a batch that was never received
/// on one (opening stock, Stock Entry receipts) falls back to its
/// manufacturing date, then to the day the Batch record was created.
BatchAge? resolveBatchAge({
  DateTime? firstReceipt,
  DateTime? manufacturing,
  DateTime? creation,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  if (firstReceipt != null) return BatchAge(day(firstReceipt), fromReceipt: true);
  final fallback = manufacturing ?? creation;
  return fallback == null ? null : BatchAge(day(fallback), fromReceipt: false);
}

/// Stock of one batch in one warehouse.
class BatchStockLine {
  const BatchStockLine({
    required this.batchNo,
    required this.warehouse,
    required this.qty,
  });

  final String batchNo;
  final String warehouse;
  final double qty;
}

/// Quantity of one batch sitting on a draft document. Drafts do not move
/// stock, so this is taken off the balance before judging what is left.
class BatchDraftLine {
  const BatchDraftLine({
    required this.batchNo,
    required this.warehouse,
    required this.qty,
    this.doctype,
    this.docName,
  });

  final String batchNo;
  final String warehouse;
  final double qty;

  /// The document the line sits on, so the open document's saved rows can be
  /// left out in favour of its in-memory rows.
  final String? doctype;
  final String? docName;
}

/// An older batch that still has stock to ship.
class OlderBatch {
  const OlderBatch({
    required this.batchNo,
    required this.age,
    required this.availableQty,
    required this.qtyByWarehouse,
  });

  final String batchNo;
  final BatchAge age;

  /// Stock left after draft quantities, across [qtyByWarehouse].
  final double availableQty;

  /// Warehouse → quantity left there (only warehouses with something left).
  final Map<String, double> qtyByWarehouse;
}

/// Thrown when a batch that matters has no known age. The caller must refuse
/// rather than guess: a missing date means a lookup came back short.
class BatchAgeUnknown implements Exception {
  const BatchAgeUnknown(this.batchNo);
  final String batchNo;

  @override
  String toString() => 'BatchAgeUnknown: no age for batch "$batchNo"';
}

/// The batches that must ship before [batchNo], oldest first.
///
/// [stock] is what the books hold for the item; lines outside the `WH-`
/// warehouses are ignored. [drafts] is taken off per warehouse and per batch,
/// never below zero. A batch with the same age day as [batchNo] is not older.
///
/// Throws [BatchAgeUnknown] when [batchNo], or a batch that still has stock,
/// is missing from [ages].
List<OlderBatch> findOlderBatches({
  required String batchNo,
  required Iterable<BatchStockLine> stock,
  required Map<String, BatchAge> ages,
  Iterable<BatchDraftLine> drafts = const [],
}) {
  final scanned = batchNo.trim();

  // (batch, warehouse) → quantity on drafts.
  final drafted = <String, double>{};
  for (final d in drafts) {
    if (d.qty <= 0) continue;
    final key = _key(d.batchNo, d.warehouse);
    drafted[key] = (drafted[key] ?? 0) + d.qty;
  }

  // batch → warehouse → quantity left.
  final left = <String, Map<String, double>>{};
  for (final s in stock) {
    final batch = s.batchNo.trim();
    if (batch.isEmpty || batch == scanned) continue;
    if (!batchAgeRuleApplies(s.warehouse)) continue;
    final byWarehouse = left.putIfAbsent(batch, () => <String, double>{});
    final wh = s.warehouse.trim();
    byWarehouse[wh] = (byWarehouse[wh] ?? 0) + s.qty;
  }

  final candidates = <String, Map<String, double>>{};
  left.forEach((batch, byWarehouse) {
    final remaining = <String, double>{};
    byWarehouse.forEach((wh, qty) {
      final net = qty - (drafted[_key(batch, wh)] ?? 0);
      if (net > kBatchAgeQtyEpsilon) remaining[wh] = net;
    });
    if (remaining.isNotEmpty) candidates[batch] = remaining;
  });
  if (candidates.isEmpty) return const [];

  final scannedAge = ages[scanned];
  if (scannedAge == null) throw BatchAgeUnknown(scanned);

  final older = <OlderBatch>[];
  candidates.forEach((batch, remaining) {
    final age = ages[batch];
    if (age == null) throw BatchAgeUnknown(batch);
    if (!age.date.isBefore(scannedAge.date)) return;
    older.add(OlderBatch(
      batchNo: batch,
      age: age,
      availableQty: remaining.values.fold(0.0, (a, b) => a + b),
      qtyByWarehouse: remaining,
    ));
  });

  older.sort((a, b) {
    final byDate = a.age.date.compareTo(b.age.date);
    return byDate != 0 ? byDate : a.batchNo.compareTo(b.batchNo);
  });
  return older;
}

/// Batches on the open document that an edit would leave out of order.
///
/// [linesBefore] and [linesAfter] are the document's own lines for the item
/// before and after the edit (a reduced quantity, a removed row). A batch is
/// reported when it is refused afterwards but was acceptable before — rows
/// that already broke the rule (added by a supervisor in Desk, or saved before
/// the rule existed) are left alone.
List<String> batchesPutOutOfOrder({
  required Iterable<BatchStockLine> stock,
  required Map<String, BatchAge> ages,
  required Iterable<BatchDraftLine> otherDrafts,
  required List<BatchDraftLine> linesBefore,
  required List<BatchDraftLine> linesAfter,
}) {
  bool refused(String batch, List<BatchDraftLine> own) => findOlderBatches(
        batchNo: batch,
        stock: stock,
        ages: ages,
        drafts: [...otherDrafts, ...own],
      ).isNotEmpty;

  Set<String> batchesOn(List<BatchDraftLine> lines) => {
        for (final l in lines)
          if (l.qty > 0 &&
              l.batchNo.trim().isNotEmpty &&
              batchAgeRuleApplies(l.warehouse))
            l.batchNo.trim(),
      };

  final before = batchesOn(linesBefore);
  final broken = <String>[];
  for (final batch in batchesOn(linesAfter)) {
    if (!refused(batch, linesAfter)) continue;
    final alreadyBroken = before.contains(batch) && refused(batch, linesBefore);
    if (!alreadyBroken) broken.add(batch);
  }
  broken.sort();
  return broken;
}

String _key(String batch, String warehouse) =>
    '${batch.trim()}\u0000${warehouse.trim()}';
