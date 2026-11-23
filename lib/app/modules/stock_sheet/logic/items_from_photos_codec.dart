import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';
import 'package:multimax/app/shared/barcode/ean8.dart';

/// Turns raw barcode text read from a photo into item codes.
class ItemsFromPhotosCodec {
  const ItemsFromPhotosCodec._();

  /// `{EAN8}-{BatchID}` with an alphanumeric batch ID.
  static final RegExp _batchQr = RegExp(r'^(\d{8})-[A-Za-z0-9]+$');

  /// A bare item code typed without its check digit.
  static final RegExp _sevenDigits = RegExp(r'^\d{7}$');

  /// Classifies one raw value as a plain EAN-8 or an `{EAN8}-{BatchID}` QR.
  /// Anything else (EAN-13, Code 128 text, a bad checksum) returns null.
  static ClassifiedCode? classify(String raw) {
    final code = raw.trim();
    if (!code.contains('-')) {
      if (!Ean8.isValid(code)) return null;
      return ClassifiedCode(
        itemCode: code.substring(0, 7),
        barcode: code,
      );
    }
    final match = _batchQr.firstMatch(code);
    if (match == null) return null;
    final prefix = match.group(1)!;
    if (!Ean8.isValid(prefix)) return null;
    return ClassifiedCode(
      itemCode: prefix.substring(0, 7),
      barcode: prefix,
      batchNo: code,
    );
  }

  /// Resolves text typed by the user. Tries [classify] first; otherwise exactly
  /// seven digits are an item code, and the EAN-8 is built with its check
  /// digit. Anything else returns null.
  static ClassifiedCode? resolveTyped(String input) {
    final code = input.trim();
    final classified = classify(code);
    if (classified != null) return classified;
    if (!_sevenDigits.hasMatch(code)) return null;
    return ClassifiedCode(
      itemCode: code,
      barcode: Ean8.withCheckDigit(code),
      batchNo: null,
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
