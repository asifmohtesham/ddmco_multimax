import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';

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

  /// Rack-wise stock per `item_code` from dimension-wise Stock Balance rows.
  /// A null or blank `rack` means "No rack". `total` sums every row of the
  /// item; `racks` keeps only positive quantities, largest first. Rows with
  /// no `item_code` or an unparsable `bal_qty` are skipped.
  static Map<String, ItemStock> racksByItem(
    List<Map<String, dynamic>> rows,
  ) {
    final totals = <String, double>{};
    final perRack = <String, Map<String?, double>>{};
    for (final row in rows) {
      final code = row['item_code']?.toString().trim() ?? '';
      if (code.isEmpty) continue;
      final raw = row['bal_qty'];
      final qty = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (qty == null) continue;
      final rackText = row['rack']?.toString().trim();
      final rack = (rackText == null || rackText.isEmpty) ? null : rackText;
      totals[code] = (totals[code] ?? 0) + qty;
      final racks = perRack.putIfAbsent(code, () => <String?, double>{});
      racks[rack] = (racks[rack] ?? 0) + qty;
    }
    return {
      for (final code in totals.keys)
        code: ItemStock(
          total: totals[code]!,
          racks: [
            for (final e in perRack[code]!.entries)
              if (e.value > 0) RackQty(rack: e.key, qty: e.value),
          ]..sort((a, b) => b.qty.compareTo(a.qty)),
        ),
    };
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
  static ItemsFromPhotosResult build(
    List<PhotoScan> scans,
    Map<String, ItemInfo> items,
    Map<String, double> stock,
  ) {
    final rows = <ItemsFromPhotosRow>[];
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
        rows.add(ItemsFromPhotosRow(
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
    return ItemsFromPhotosResult(rows: rows, unresolved: unresolved);
  }
}
