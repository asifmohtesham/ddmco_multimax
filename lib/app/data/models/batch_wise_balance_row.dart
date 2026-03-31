/// A single row returned by the Batch-Wise Balance History report
/// for a given item + warehouse combination.
///
/// Used by [BatchPickerSheet] to display available batches with live
/// balance data so operators can select the right batch without
/// knowing batch numbers in advance.
class BatchWiseBalanceRow {
  final String batchNo;
  final double balanceQty;
  final DateTime? expiryDate;
  final String warehouse;

  const BatchWiseBalanceRow({
    required this.batchNo,
    required this.balanceQty,
    required this.warehouse,
    this.expiryDate,
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

  /// Parse a row from the Batch-Wise Balance History report result.
  ///
  /// The report returns rows as [List<dynamic>] where column order is:
  ///   [0] batch_id, [1] expiry_date, [2] warehouse,
  ///   [3] opening_qty, [4] in_qty, [5] out_qty, [6] balance_qty
  ///
  /// Column indices are resolved dynamically via [columnIndex] to guard
  /// against ERPNext version differences.
  factory BatchWiseBalanceRow.fromReportRow(
    List<dynamic> row, {
    required int batchIdx,
    required int balanceIdx,
    required int warehouseIdx,
    required int expiryIdx,
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

    return BatchWiseBalanceRow(
      batchNo:    batchNo,
      balanceQty: balanceQty,
      warehouse:  warehouse,
      expiryDate: expiry,
    );
  }
}
