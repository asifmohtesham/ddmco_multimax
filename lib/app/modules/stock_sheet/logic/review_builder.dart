import '../model/review_models.dart';
import '../model/stock_sheet_models.dart';

/// Pure operations on the review list. Every method returns new lists and
/// entries; inputs are never mutated.
class ReviewBuilder {
  const ReviewBuilder._();

  /// Builds an entry from a decoded photo. Codes found in [items] become
  /// included items; the rest are listed in `notInErp`.
  static ReviewEntry entryFor(
    PhotoScan scan,
    Map<String, ItemInfo> items,
    Map<String, ItemStock> stock,
  ) {
    final found = <ReviewItem>[];
    final missing = <String>[];
    for (final code in scan.items) {
      final info = items[code.itemCode];
      if (info == null) {
        missing.add(code.barcode);
      } else {
        found.add(ReviewItem(
          code: code,
          info: info,
          stock: stock[code.itemCode],
          included: true,
        ));
      }
    }
    return ReviewEntry(
      path: scan.path,
      decodeFailed: scan.decodeFailed,
      rawValues: scan.rawValues,
      items: found,
      notInErp: missing,
    );
  }

  /// Row switch: turns every item of the entry on or off. No-op when the
  /// entry is unresolved.
  static List<ReviewEntry> setIncluded(
      List<ReviewEntry> list, int index, bool on) {
    final entry = list[index];
    if (!entry.resolved) return List.of(list);
    return _replace(
      list,
      index,
      entry.copyWith(
        items: [for (final i in entry.items) i.copyWith(included: on)],
      ),
    );
  }

  static List<ReviewEntry> setItemIncluded(
      List<ReviewEntry> list, int index, int itemIndex, bool on) {
    final entry = list[index];
    final items = List.of(entry.items);
    items[itemIndex] = items[itemIndex].copyWith(included: on);
    return _replace(list, index, entry.copyWith(items: items));
  }

  /// `ReorderableListView` semantics: [newIndex] is the slot before removal.
  static List<ReviewEntry> reorder(
      List<ReviewEntry> list, int oldIndex, int newIndex) {
    final out = List.of(list);
    if (newIndex > oldIndex) newIndex -= 1;
    out.insert(newIndex, out.removeAt(oldIndex));
    return out;
  }

  /// Entries with at least one included item.
  static int sheetPhotoCount(List<ReviewEntry> list) =>
      list.where((e) => e.included).length;

  /// Rows for every included item, and one unresolved entry per photo that
  /// resolved nothing. Rack and quantity never reach the result.
  static StockSheetResult toResult(List<ReviewEntry> list) {
    final rows = <StockSheetRow>[];
    final unresolved = <UnresolvedEntry>[];
    for (var p = 0; p < list.length; p++) {
      final entry = list[p];
      if (entry.resolved) {
        for (final item in entry.items.where((i) => i.included)) {
          rows.add(StockSheetRow(
            photoIndex: p,
            photoPath: entry.path,
            barcode: item.code.barcode,
            itemName: item.info.itemName,
            variantOf: item.info.variantOf,
            countryOfOrigin: item.info.countryOfOrigin,
            outOfStock: item.stock == null || item.stock!.outOfStock,
          ));
        }
      } else if (entry.decodeFailed) {
        unresolved.add(UnresolvedEntry(
            photoIndex: p,
            photoPath: entry.path,
            reason: UnresolvedReason.unreadable));
      } else if (entry.notInErp.isNotEmpty) {
        unresolved.add(UnresolvedEntry(
            photoIndex: p,
            photoPath: entry.path,
            reason: UnresolvedReason.notInErp,
            barcode: entry.notInErp.first));
      } else {
        unresolved.add(UnresolvedEntry(
            photoIndex: p,
            photoPath: entry.path,
            reason: UnresolvedReason.noRecognisedCode));
      }
    }
    return StockSheetResult(rows: rows, unresolved: unresolved);
  }

  static List<ReviewEntry> _replace(
      List<ReviewEntry> list, int index, ReviewEntry entry) {
    final out = List.of(list);
    out[index] = entry;
    return out;
  }
}
