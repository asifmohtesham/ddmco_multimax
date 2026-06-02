/// A single row returned by the Batch-Wise Balance History report
/// for a given item + warehouse combination.
///
/// Used by [BatchPickerSheet] to display available batches with live
/// balance data so operators can select the right batch without
/// knowing batch numbers in advance.
///
/// ## ERPNext Batch-Wise Balance History — field-name reference
///
/// The canonical documentation for ERPNext column keys and the Total Row
/// discard invariant lives on [BatchNoBrowseDelegate].  The two factory
/// constructors below ([fromMap] and [fromReportRow]) each carry a
/// field-name table that cross-references that source.
///
/// Quick reference:
///   - `"batch"`       → [batchNo]    (primary key for the batch identifier)
///   - `"balance_qty"` → [balanceQty] (available stock qty)
///   - `"item"`        → Item Code — server-side filter only; not stored here
///
/// ## Total Row — caller responsibility
///
/// The Batch-Wise Balance History report **always appends a Total Row as
/// its last entry**.  This class has no visibility into row position, so
/// it cannot detect or discard the Total Row itself.  The caller
/// ([ApiProvider.getBatchWiseBalance] / [ApiProvider.fetchBatchesForItem])
/// MUST remove the last row before constructing [BatchWiseBalanceRow]
/// instances.  See [BatchNoBrowseDelegate] for the canonical discard
/// contract and guard snippet.
///
/// Commit 1: added [packagingQty] parsed from the `custom_packaging_qty`
/// column in the report result. The column index is resolved dynamically
/// by [BatchWiseBalanceRow.fromReportRow] via the caller-supplied
/// [packagingIdx]; absent columns default to 0.0 (no change to callers
/// that pass -1).
///
/// Commit 5: added [fromMap] factory so that callers receiving
/// Map<String,dynamic> rows from [ApiProvider.getBatchWiseBalance] (the
/// key-based path) can construct a [BatchWiseBalanceRow] without going
/// through [fromReportRow] (which expects index-based List rows).
///
/// Commit 4 of 7 (SharedBatchField refactor): added Dartdoc tables for
/// ERPNext field names and Total Row invariant on [fromMap] and
/// [fromReportRow]. Zero logic changes.
class BatchWiseBalanceRow {
  final String batchNo;
  final double balanceQty;
  final DateTime? expiryDate;
  final String warehouse;

  /// Qty per package/carton, sourced from `custom_packaging_qty` on the Batch
  /// DocType.  0.0 when the field is absent or the column was not in the report.
  final double packagingQty;

  const BatchWiseBalanceRow({
    required this.batchNo,
    required this.balanceQty,
    required this.warehouse,
    this.expiryDate,
    this.packagingQty = 0.0,
  });

  /// Whether this batch expires within the next [days] days.
  bool expiresWithin(int days) {
    if (expiryDate == null) return false;
    final cutoff = DateTime.now().add(Duration(days: days));
    return expiryDate!.isBefore(cutoff);
  }

  /// True when the batch has expired (expiry date is in the past).
  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  // ── fromMap ───────────────────────────────────────────────────────────────────────────
  /// Construct from a key-based [Map<String, dynamic>] row as returned by
  /// [ApiProvider.getBatchWiseBalance] (the Map path — when the report returns
  /// keyed objects rather than raw List rows).
  ///
  /// ## ERPNext Batch-Wise Balance History — field names
  ///
  /// | Dart field      | Primary key     | Fallback keys                     |
  /// |-----------------|-----------------|-----------------------------------|
  /// | [batchNo]       | `"batch"`       | `"batch_no"`, `"batch_id"`        |
  /// | [balanceQty]    | `"balance_qty"` | `"qty"`, `"bal_qty"`, `"balance"` |
  /// | [warehouse]     | `"warehouse"`   | —                                 |
  /// | [expiryDate]    | `"expiry_date"` | `"expiration_date"`               |
  /// | [packagingQty]  | `"custom_packaging_qty"` | `"packaging_qty"`      |
  ///
  /// The `"item"` column (Item Code) is a **server-side filter parameter**
  /// applied when requesting the report.  It is not present in individual
  /// row maps and is not stored on this model — the caller already holds
  /// the item code.
  ///
  /// ## Total Row — caller responsibility
  ///
  /// This factory parses a single row and has no visibility into whether
  /// it is the Total Row footer appended by the report.  The **caller**
  /// ([ApiProvider]) must discard the last row of the raw result before
  /// constructing [BatchWiseBalanceRow] instances.  See
  /// [BatchNoBrowseDelegate] for the canonical discard contract and the
  /// cross-file traceability chain.
  factory BatchWiseBalanceRow.fromMap(Map<String, dynamic> map) {
    final batchNo = (map['batch_no'] ?? map['batch'] ?? map['batch_id'] ?? '')
        .toString()
        .trim();

    double toDouble(dynamic v) => switch (v) {
          final num n    => n.toDouble(),
          final String s => double.tryParse(s) ?? 0.0,
          _              => 0.0,
        };

    final balanceQty = toDouble(
        map['qty'] ?? map['balance_qty'] ?? map['bal_qty'] ?? map['balance']);

    final warehouse =
        (map['warehouse'] ?? '').toString().trim();

    DateTime? expiryDate;
    final rawExpiry = map['expiry_date'] ?? map['expiration_date'];
    if (rawExpiry != null && rawExpiry.toString().isNotEmpty) {
      expiryDate = DateTime.tryParse(rawExpiry.toString());
    }

    final packagingQty = toDouble(
        map['custom_packaging_qty'] ?? map['packaging_qty']);

    return BatchWiseBalanceRow(
      batchNo:      batchNo,
      balanceQty:   balanceQty,
      warehouse:    warehouse,
      expiryDate:   expiryDate,
      packagingQty: packagingQty,
    );
  }

  // ── fromReportRow ───────────────────────────────────────────────────────────────────────
  /// Parse a row from the Batch-Wise Balance History report result.
  ///
  /// Column indices are resolved dynamically by the caller (see
  /// [ApiProvider.fetchBatchesForItem]) so this factory is resilient to
  /// ERPNext version differences that shift column ordering.
  ///
  /// ## ERPNext Batch-Wise Balance History — column-to-field mapping
  ///
  /// | Index param      | ERPNext column key        | Dart field      |
  /// |------------------|---------------------------|-----------------|
  /// | [batchIdx]       | `"batch"`                 | [batchNo]       |
  /// | [balanceIdx]     | `"balance_qty"`           | [balanceQty]    |
  /// | [warehouseIdx]   | `"warehouse"`             | [warehouse]     |
  /// | [expiryIdx]      | `"expiry_date"`           | [expiryDate]    |
  /// | [packagingIdx]   | `"custom_packaging_qty"`  | [packagingQty]  |
  ///
  /// The `"item"` column (Item Code) is a **server-side filter parameter**
  /// supplied when requesting the report.  It is not parsed into this
  /// model — the caller already holds the item code.
  ///
  /// ## Total Row — caller responsibility
  ///
  /// The raw Batch-Wise Balance History report result **always includes a
  /// Total Row as its last entry**.  This factory has no visibility into
  /// row position within the report — it parses exactly the row it
  /// receives.  A Total Row passed to this factory will produce a
  /// [BatchWiseBalanceRow] with an **empty [batchNo]**, which would appear
  /// as a blank, unselectable entry in [BatchPickerSheet].
  ///
  /// The caller ([ApiProvider.getBatchWiseBalance] /
  /// [ApiProvider.fetchBatchesForItem]) MUST remove the last row from the
  /// raw result before iterating and calling [fromReportRow].  See
  /// [BatchNoBrowseDelegate] for the canonical discard contract and guard.
  ///
  /// Pass [packagingIdx] == -1 (or omit) when the column is absent.
  factory BatchWiseBalanceRow.fromReportRow(
    List<dynamic> row, {
    required int batchIdx,
    required int balanceIdx,
    required int warehouseIdx,
    required int expiryIdx,
    int packagingIdx = -1,
  }) {
    final batchNo    = row[batchIdx]?.toString().trim() ?? '';
    final warehouse  = row[warehouseIdx]?.toString().trim() ?? '';
    final balanceQty = switch (row[balanceIdx]) {
      final num n    => n.toDouble(),
      final String s => double.tryParse(s) ?? 0.0,
      _              => 0.0,
    };

    DateTime? expiry;
    final rawExpiry = row[expiryIdx];
    if (rawExpiry != null && rawExpiry.toString().isNotEmpty) {
      expiry = DateTime.tryParse(rawExpiry.toString());
    }

    double packagingQty = 0.0;
    if (packagingIdx >= 0 && packagingIdx < row.length) {
      packagingQty = switch (row[packagingIdx]) {
        final num n    => n.toDouble(),
        final String s => double.tryParse(s) ?? 0.0,
        _              => 0.0,
      };
    }

    return BatchWiseBalanceRow(
      batchNo:      batchNo,
      balanceQty:   balanceQty,
      warehouse:    warehouse,
      expiryDate:   expiry,
      packagingQty: packagingQty,
    );
  }
}
