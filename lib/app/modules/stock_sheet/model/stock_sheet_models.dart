import 'dart:typed_data';

/// A label code recognised in a photo: the item it belongs to, the EAN-8 it
/// was derived from, and the batch QR text when the label carried one.
class ClassifiedCode {
  const ClassifiedCode({
    required this.itemCode,
    required this.barcode,
    this.batchNo,
  });

  /// First seven digits of the EAN-8.
  final String itemCode;

  /// The validated EAN-8.
  final String barcode;

  /// The full `{EAN8}-{BatchID}` text, or null for a plain EAN-8.
  final String? batchNo;

  @override
  bool operator ==(Object other) =>
      other is ClassifiedCode &&
      other.itemCode == itemCode &&
      other.barcode == barcode &&
      other.batchNo == batchNo;

  @override
  int get hashCode => Object.hash(itemCode, barcode, batchNo);

  @override
  String toString() =>
      'ClassifiedCode($itemCode, $barcode, batchNo: $batchNo)';
}

/// What one shared photo yielded: the raw decoded strings and the item codes
/// recognised among them.
class PhotoScan {
  const PhotoScan({
    required this.index,
    required this.path,
    this.rawValues = const [],
    this.items = const [],
    this.decodeFailed = false,
  });

  /// Zero-based position of the photo in the share.
  final int index;
  final String path;

  /// Every barcode/QR string decoded from the photo, recognised or not.
  final List<String> rawValues;

  /// The recognised codes, in the order they were read.
  final List<ClassifiedCode> items;

  /// True when the photo could not be decoded at all.
  final bool decodeFailed;
}

/// The Item fields the sheet shows.
class ItemInfo {
  const ItemInfo({
    required this.itemCode,
    this.itemName,
    this.variantOf,
    this.countryOfOrigin,
  });

  final String itemCode;
  final String? itemName;
  final String? variantOf;
  final String? countryOfOrigin;
}

/// Balance quantity held in one rack; [rack] is null for "No rack".
class RackQty {
  const RackQty({required this.rack, required this.qty});

  final String? rack;
  final double qty;

  @override
  bool operator ==(Object other) =>
      other is RackQty && other.rack == rack && other.qty == qty;

  @override
  int get hashCode => Object.hash(rack, qty);

  @override
  String toString() => 'RackQty($rack, $qty)';
}

/// One item's Finished Goods stock: the [total] over every row and the racks
/// that hold some, largest first (only racks with a positive quantity).
class ItemStock {
  const ItemStock({required this.total, required this.racks});

  final double total;
  final List<RackQty> racks;

  bool get outOfStock => total <= 0;
}

/// One sheet row: a single item found in a single photo.
class StockSheetRow {
  const StockSheetRow({
    required this.photoIndex,
    required this.photoPath,
    required this.barcode,
    this.itemName,
    this.variantOf,
    this.countryOfOrigin,
    this.outOfStock = false,
  });

  final int photoIndex;
  final String photoPath;
  final String barcode;
  final String? itemName;
  final String? variantOf;
  final String? countryOfOrigin;
  final bool outOfStock;
}

enum UnresolvedReason { unreadable, noRecognisedCode, notInErp }

/// A photo, or a code in a photo, that produced no sheet row.
class UnresolvedEntry {
  const UnresolvedEntry({
    required this.photoIndex,
    required this.photoPath,
    required this.reason,
    this.barcode,
  });

  final int photoIndex;
  final String photoPath;
  final UnresolvedReason reason;

  /// Set for [UnresolvedReason.notInErp].
  final String? barcode;
}

class StockSheetResult {
  const StockSheetResult({required this.rows, required this.unresolved});

  final List<StockSheetRow> rows;
  final List<UnresolvedEntry> unresolved;

  int get outOfStockCount => rows.where((r) => r.outOfStock).length;
}

/// The user may not read Item or Stock Balance (HTTP 403). Never treated as
/// "everything is out of stock".
class StockAccessDenied implements Exception {
  const StockAccessDenied();

  @override
  String toString() => 'StockAccessDenied';
}

/// Everything a writer needs to render the sheet.
class StockSheetDocument {
  const StockSheetDocument({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.thumbnails,
    this.highlightOutOfStock = true,
    this.showStatus = false,
  });

  final String title;
  final String subtitle;
  final List<StockSheetRow> rows;

  /// JPEG thumbnails keyed by [StockSheetRow.photoPath].
  final Map<String, Uint8List> thumbnails;

  /// Colour out-of-stock rows red.
  final bool highlightOutOfStock;

  /// Add the trailing `Stock` column.
  final bool showStatus;
}
