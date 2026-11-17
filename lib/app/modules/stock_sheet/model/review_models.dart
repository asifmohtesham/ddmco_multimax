import 'stock_sheet_models.dart';

/// One resolved item in a review entry: the code read from the photo, its Item
/// details, its Finished Goods stock (null when unknown) and whether it goes
/// on the sheet.
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

/// One photo in the review list.
class ReviewEntry {
  ReviewEntry({
    required this.path,
    this.decodeFailed = false,
    List<String> rawValues = const [],
    List<ReviewItem> items = const [],
    List<String> notInErp = const [],
    this.typed = false,
    this.unchecked = false,
  })  : rawValues = List.unmodifiable(rawValues),
        items = List.unmodifiable(items),
        notInErp = List.unmodifiable(notInErp);

  final String path;
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
        decodeFailed: decodeFailed ?? this.decodeFailed,
        rawValues: rawValues ?? this.rawValues,
        items: items ?? this.items,
        notInErp: notInErp ?? this.notInErp,
        typed: typed ?? this.typed,
        unchecked: unchecked ?? this.unchecked,
      );
}
