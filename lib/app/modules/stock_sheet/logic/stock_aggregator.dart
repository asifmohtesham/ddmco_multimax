import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';

class StockAggregator {
  const StockAggregator._();

  /// Sums `bal_qty` per `item_code` across Stock Balance rows. `bal_qty` may
  /// be an int, a double or a numeric string; rows without an `item_code`
  /// (or with an unparsable quantity) are skipped.
  static Map<String, double> sumByItem(List<Map<String, dynamic>> reportRows) {
    final totals = <String, double>{};
    for (final row in reportRows) {
      final code = row['item_code']?.toString().trim() ?? '';
      if (code.isEmpty) continue;
      final raw = row['bal_qty'];
      final qty = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (qty == null) continue;
      totals[code] = (totals[code] ?? 0) + qty;
    }
    return totals;
  }

  /// Builds the sheet rows and the unresolved list.
  ///
  /// Rules:
  /// - Rows follow photo order, then the order of codes within each photo.
  /// - A scan with `decodeFailed` gives one `unreadable` entry and no rows.
  /// - A scan with no classified items gives one `noRecognisedCode` entry.
  /// - A classified item missing from [items] gives a `notInErp` entry
  ///   carrying its barcode; the photo's other items still get rows.
  /// - A row is out of stock when `(stock[code] ?? 0) <= 0`.
  /// - The same item in two photos gives two rows (one per photo).
  static StockSheetResult build(
    List<PhotoScan> scans,
    Map<String, ItemInfo> items,
    Map<String, double> stock,
  ) {
    final rows = <StockSheetRow>[];
    final unresolved = <UnresolvedEntry>[];
    for (final scan in scans) {
      if (scan.decodeFailed) {
        unresolved.add(UnresolvedEntry(
          photoIndex: scan.index,
          photoPath: scan.path,
          reason: UnresolvedReason.unreadable,
        ));
        continue;
      }
      if (scan.items.isEmpty) {
        unresolved.add(UnresolvedEntry(
          photoIndex: scan.index,
          photoPath: scan.path,
          reason: UnresolvedReason.noRecognisedCode,
        ));
        continue;
      }
      for (final code in scan.items) {
        final info = items[code.itemCode];
        if (info == null) {
          unresolved.add(UnresolvedEntry(
            photoIndex: scan.index,
            photoPath: scan.path,
            reason: UnresolvedReason.notInErp,
            barcode: code.barcode,
          ));
          continue;
        }
        rows.add(StockSheetRow(
          photoIndex: scan.index,
          photoPath: scan.path,
          barcode: code.barcode,
          itemName: info.itemName,
          variantOf: info.variantOf,
          countryOfOrigin: info.countryOfOrigin,
          outOfStock: (stock[code.itemCode] ?? 0) <= 0,
        ));
      }
    }
    return StockSheetResult(rows: rows, unresolved: unresolved);
  }
}
