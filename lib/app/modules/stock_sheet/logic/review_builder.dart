import '../model/review_models.dart';
import '../model/items_from_photos_models.dart';

/// Pure operations on the review list. Every method returns new lists and
/// entries; inputs are never mutated.
class ReviewBuilder {
  const ReviewBuilder._();

  /// The review rows of a decoded photo: one per item found in [items], in
  /// the order the codes were read, then one per code [items] does not know
  /// ("Not in ERP"). A photo that gave neither is one unresolved row. Rows
  /// of a photo with several share its [PhotoScan.path] and its raw values;
  /// their [ReviewEntry.id]s tell them apart.
  static List<ReviewEntry> entriesFor(
    PhotoScan scan,
    Map<String, ItemInfo> items,
    Map<String, ItemStock> stock,
  ) {
    final rows = <ReviewEntry>[];
    final missing = <String>[];
    for (final code in scan.items) {
      final info = items[code.itemCode];
      if (info == null) {
        missing.add(code.barcode);
        continue;
      }
      rows.add(ReviewEntry(
        path: scan.path,
        rawValues: scan.rawValues,
        items: [
          ReviewItem(
            code: code,
            info: info,
            stock: stock[code.itemCode],
            included: true,
          ),
        ],
      ));
    }
    for (final barcode in missing) {
      rows.add(ReviewEntry(
        path: scan.path,
        rawValues: scan.rawValues,
        notInErp: [barcode],
      ));
    }
    if (rows.isEmpty) {
      return [
        ReviewEntry(
          path: scan.path,
          decodeFailed: scan.decodeFailed,
          rawValues: scan.rawValues,
        ),
      ];
    }
    if (rows.length == 1) return rows;
    return [
      for (var k = 0; k < rows.length; k++)
        ReviewEntry(
          path: rows[k].path,
          id: '${scan.path}#$k',
          rawValues: rows[k].rawValues,
          items: rows[k].items,
          notInErp: rows[k].notInErp,
        ),
    ];
  }

  /// Row switch: turns the row's item on or off. No-op when the row is
  /// unresolved.
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

  /// `ReorderableListView` semantics: [newIndex] is the slot before removal.
  static List<ReviewEntry> reorder(
      List<ReviewEntry> list, int oldIndex, int newIndex) {
    final out = List.of(list);
    if (newIndex > oldIndex) newIndex -= 1;
    out.insert(newIndex, out.removeAt(oldIndex));
    return out;
  }

  /// Photos with at least one row on the sheet.
  static int sheetPhotoCount(List<ReviewEntry> list) =>
      {for (final e in list) if (e.included) e.path}.length;

  /// Rows on the sheet: one per item switched on.
  static int sheetItemCount(List<ReviewEntry> list) => list
      .expand((e) => e.items)
      .where((i) => i.included)
      .length;

  /// Distinct photos in the list.
  static int photoCount(List<ReviewEntry> list) =>
      {for (final e in list) e.path}.length;

  /// Rows for every included item, and one unresolved entry per photo that
  /// resolved nothing. Rack and quantity never reach the result.
  static StockSheetResult toResult(List<ReviewEntry> list) {
    final rows = <StockSheetRow>[];
    final unresolved = <UnresolvedEntry>[];
    // The photo's number in the list, counting each photo once however many
    // rows it gave.
    final photoNumber = <String, int>{};
    for (final entry in list) {
      final p = photoNumber.putIfAbsent(entry.path, () => photoNumber.length);
      if (entry.resolved) {
        for (final item in entry.items.where((i) => i.included)) {
          rows.add(StockSheetRow(
            photoIndex: p,
            photoPath: entry.path,
            barcode: item.code.barcode,
            imageKey: item.info.image == null
                ? null
                : ItemInfo.thumbnailKey(item.info.itemCode),
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
