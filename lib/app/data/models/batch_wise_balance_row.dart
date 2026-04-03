/// A single row returned by the Batch-Wise Balance History report
/// for a given item + warehouse combination.
///
/// Used by [BatchPickerSheet] to display available batches with live
/// balance data so operators can select the right batch without
/// knowing batch numbers in advance.
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

  // ── fromMap ───────────────────────────────────────────────────────────────
  /// Construct from a key-based [Map<String, dynamic>] row as returned by
  /// [ApiProvider.getBatchWiseBalance] (the Map path — when the report returns
  /// keyed objects rather than raw List rows).
  ///
  /// Recognised keys:
  ///   batch_no | batch | batch_id  → [batchNo]
  ///   qty | balance_qty | bal_qty  → [balanceQty]
  ///   warehouse                    → [warehouse]
  ///   expiry_date | expiration_date → [expiryDate]
  ///   custom_packaging_qty | packaging_qty → [packagingQty]
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

  // ── fromReportRow ─────────────────────────────────────────────────────────
  /// Parse a row from the Batch-Wise Balance History report result.
  ///
  /// Column indices are resolved dynamically by the caller (see
  /// [ApiProvider.fetchBatchesForItem]) so this factory is resilient to
  /// ERPNext version differences.
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
