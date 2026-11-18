import 'stock_sheet_models.dart';

/// One resolved item in a review entry: the code read from the photo, its Item
/// details, its Finished Goods stock and whether it goes on the sheet. An item
/// exists only after a successful stock check, so a null stock means it has
/// no Stock Balance row: out of stock.
class ReviewItem {
  const ReviewItem({
    required this.code,
    required this.info,
    this.stock,
    this.included = true,
  });

  final ClassifiedCode code;
  final ItemInfo info;
  final ItemStock? stock;
  final bool included;

  ReviewItem copyWith({bool? included}) => ReviewItem(
        code: code,
        info: info,
        stock: stock,
        included: included ?? this.included,
      );
}

/// One row of the review list: one item read from a photo, or a photo (or a
/// code in it) that resolved to no item. A photo holding several items gives
/// one row per item, all with the same [path].
class ReviewEntry {
  ReviewEntry({
    required this.path,
    String? id,
    this.decodeFailed = false,
    List<String> rawValues = const [],
    List<ReviewItem> items = const [],
    List<String> notInErp = const [],
    this.typed = false,
    this.unchecked = false,
  })  : id = id ?? path,
        rawValues = List.unmodifiable(rawValues),
        items = List.unmodifiable(items),
        notInErp = List.unmodifiable(notInErp);

  final String path;

  /// Tells the rows of one photo apart; the [path] when the photo has one.
  /// Kept by [copyWith].
  final String id;

  final bool decodeFailed;

  /// Every string decoded from the photo, recognised or not.
  final List<String> rawValues;

  /// Items found in ERP.
  final List<ReviewItem> items;

  /// Barcodes read from the photo that ERP does not know.
  final List<String> notInErp;

  /// True when the code was typed or scanned by hand to fix this photo.
  final bool typed;

  /// An added photo whose stock check failed (offers "Retry check").
  final bool unchecked;

  bool get resolved => items.isNotEmpty;
  bool get included => items.any((i) => i.included);

  ReviewEntry copyWith({
    bool? decodeFailed,
    List<String>? rawValues,
    List<ReviewItem>? items,
    List<String>? notInErp,
    bool? typed,
    bool? unchecked,
  }) =>
      ReviewEntry(
        path: path,
        id: id,
        decodeFailed: decodeFailed ?? this.decodeFailed,
        rawValues: rawValues ?? this.rawValues,
        items: items ?? this.items,
        notInErp: notInErp ?? this.notInErp,
        typed: typed ?? this.typed,
        unchecked: unchecked ?? this.unchecked,
      );
}
