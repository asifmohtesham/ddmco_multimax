import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/shared/barcode/ean8.dart';

/// Turns raw barcode text read from a photo into item codes.
class StockSheetCodec {
  const StockSheetCodec._();

  /// Classifies one raw value as a plain EAN-8 or an `{EAN8}-{BatchID}` QR.
  /// Anything else (EAN-13, Code 128 text, a bad checksum) returns null.
  static ClassifiedCode? classify(String raw) {
    final code = raw.trim();
    final isBatch = code.contains('-');
    final prefix = isBatch ? code.split('-').first : code;
    if (!Ean8.isValid(prefix)) return null;
    return ClassifiedCode(
      itemCode: prefix.substring(0, 7),
      barcode: prefix,
      batchNo: isBatch ? code : null,
    );
  }

  /// Classifies every value, keeping one entry per item in first-seen order.
  /// If any code for an item was a batch QR, that entry keeps its batch.
  static List<ClassifiedCode> itemsInPhoto(List<String> rawValues) {
    final byItem = <String, ClassifiedCode>{};
    for (final raw in rawValues) {
      final found = classify(raw);
      if (found == null) continue;
      final existing = byItem[found.itemCode];
      if (existing == null || (existing.batchNo == null && found.batchNo != null)) {
        byItem[found.itemCode] = found;
      }
    }
    return byItem.values.toList();
  }
}
