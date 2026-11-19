import 'package:multimax/app/data/providers/batch_age_provider.dart';
import 'package:multimax/app/shared/item_sheet/batch_age_rule.dart';

/// Outcome of an oldest-stock-first check.
class BatchAgeVerdict {
  const BatchAgeVerdict.allowed()
      : older = const [],
        scopeWarehouse = null;

  const BatchAgeVerdict.refused(this.older, {required this.scopeWarehouse});

  /// Older batches that still have stock, oldest first. Empty = allowed.
  final List<OlderBatch> older;

  /// The warehouse (group or leaf) whose stock was judged; null when the rule
  /// did not apply.
  final String? scopeWarehouse;

  bool get isRefused => older.isNotEmpty;
}

/// Runs the oldest-stock-first rule against live stock.
///
/// Every method throws when the server cannot answer; callers refuse the
/// action in that case (fail closed). See `docs/batch_age_validation.md`.
class BatchAgeChecker {
  BatchAgeChecker([BatchAgeDataSource? source])
      : _source = source ?? ApiBatchAgeDataSource();

  /// How controllers obtain a checker. Tests replace this with a fake source.
  static BatchAgeChecker Function() create = BatchAgeChecker.new;

  final BatchAgeDataSource _source;

  /// The warehouse whose stock must be exhausted for a pick from
  /// [pickWarehouse]: its parent group, or itself at the top level.
  Future<String> scopeWarehouse(String pickWarehouse) async {
    final parent = await _source.parentWarehouse(pickWarehouse.trim());
    return (parent == null || parent.isEmpty) ? pickWarehouse.trim() : parent;
  }

  /// May [batchNo] of [itemCode] be picked from [pickWarehouse]?
  ///
  /// [ownLines] are the open document's in-memory lines for the item (minus
  /// the row being edited). Its saved rows on the server, identified by
  /// [ownDoctype] + [ownDocName], are left out so they are not counted twice.
  Future<BatchAgeVerdict> check({
    required String itemCode,
    required String? pickWarehouse,
    required String batchNo,
    List<BatchDraftLine> ownLines = const [],
    String? ownDoctype,
    String? ownDocName,
  }) async {
    if (!batchAgeRuleApplies(pickWarehouse)) {
      return const BatchAgeVerdict.allowed();
    }
    final batch = batchNo.trim();
    final scope = await scopeWarehouse(pickWarehouse!);
    final stock = await _inScopeStock(itemCode, scope);

    // Most items hold a single batch: nothing can be older, so skip the
    // age and draft lookups altogether.
    if (!stock.any((s) => s.batchNo.trim() != batch)) {
      return const BatchAgeVerdict.allowed();
    }

    final (ages, drafts) = await (
      _source.batchAges({batch, ...stock.map((s) => s.batchNo.trim())}.toList()),
      _otherDrafts(itemCode, ownDoctype, ownDocName),
    ).wait;

    final older = findOlderBatches(
      batchNo: batch,
      stock: stock,
      ages: ages,
      drafts: [...drafts, ...ownLines],
    );
    return older.isEmpty
        ? const BatchAgeVerdict.allowed()
        : BatchAgeVerdict.refused(older, scopeWarehouse: scope);
  }

  /// Why changing the open document's lines for [itemCode] from [linesBefore]
  /// to [linesAfter] is not allowed, or null when it is.
  ///
  /// Reducing or removing an older-batch row frees that stock again; a newer
  /// batch already on the document would then be out of order.
  Future<String?> orderBreakReason({
    required String itemCode,
    required String? pickWarehouse,
    required List<BatchDraftLine> linesBefore,
    required List<BatchDraftLine> linesAfter,
    String? ownDoctype,
    String? ownDocName,
  }) async {
    if (!batchAgeRuleApplies(pickWarehouse)) return null;
    final batchesAfter = {
      for (final l in linesAfter)
        if (l.qty > 0 && l.batchNo.trim().isNotEmpty) l.batchNo.trim(),
    };
    if (batchesAfter.isEmpty) return null;

    final scope = await scopeWarehouse(pickWarehouse!);
    final stock = await _inScopeStock(itemCode, scope);
    final stockBatches = {for (final s in stock) s.batchNo.trim()};
    // A single batch in stock: nothing can be older than anything.
    if (stockBatches.length <= 1) return null;

    final (ages, drafts) = await (
      _source.batchAges({
        ...stockBatches,
        ...batchesAfter,
        for (final l in linesBefore)
          if (l.batchNo.trim().isNotEmpty) l.batchNo.trim(),
      }.toList()),
      _otherDrafts(itemCode, ownDoctype, ownDocName),
    ).wait;

    final broken = batchesPutOutOfOrder(
      stock: stock,
      ages: ages,
      otherDrafts: drafts,
      linesBefore: linesBefore,
      linesAfter: linesAfter,
    );
    if (broken.isEmpty) return null;
    return 'Older stock would be left behind. Remove batch '
        '${broken.join(', ')} from this document first.';
  }

  /// Where [itemCode] is kept, by rack, in the `WH-` warehouses the rule
  /// covers for a pick from [pickWarehouse]. Item-level, largest first.
  Future<List<RackStockLine>> racks({
    required String itemCode,
    required String pickWarehouse,
    String? scope,
  }) async {
    final warehouse = scope ?? await scopeWarehouse(pickWarehouse);
    final lines =
        await _source.rackStock(itemCode: itemCode, warehouse: warehouse);
    return lines.where((l) => batchAgeRuleApplies(l.warehouse)).toList();
  }

  /// Ages for [batchNos] — used to order the batch picker oldest first.
  Future<Map<String, BatchAge>> ages(List<String> batchNos) =>
      _source.batchAges(batchNos);

  Future<List<BatchStockLine>> _inScopeStock(
      String itemCode, String scope) async {
    final stock = await _source.batchStock(itemCode: itemCode, warehouse: scope);
    return stock.where((s) => batchAgeRuleApplies(s.warehouse)).toList();
  }

  Future<List<BatchDraftLine>> _otherDrafts(
      String itemCode, String? ownDoctype, String? ownDocName) async {
    final drafts = await _source.draftLines(itemCode: itemCode);
    final own = ownDocName?.trim() ?? '';
    if (own.isEmpty) return drafts;
    return drafts
        .where((d) => !(d.doctype == ownDoctype && d.docName == own))
        .toList();
  }
}
