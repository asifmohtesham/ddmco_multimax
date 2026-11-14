enum BarcodeType { ean8, fullBatchNo, batchIdOnly, unknown }

class BarcodeRouter {
  /// Classifies a raw barcode value based on its length and content.
  ///
  /// EAN-8:        8 numeric digits          → [BarcodeType.ean8]
  /// Full Batch No: 12 or 15 chars with '-'  → [BarcodeType.fullBatchNo]
  /// Batch ID only: 3 or 6 chars             → [BarcodeType.batchIdOnly]
  /// Anything else                           → [BarcodeType.unknown]
  static BarcodeType classify(String raw) {
    final s = raw.trim();
    if (s.length == 8 && int.tryParse(s) != null) return BarcodeType.ean8;
    if ((s.length == 12 || s.length == 15) && s.contains('-')) {
      return BarcodeType.fullBatchNo;
    }
    if (s.length == 3 || s.length == 6) return BarcodeType.batchIdOnly;
    return BarcodeType.unknown;
  }

  /// Extracts the 7-digit item code from an 8-digit EAN-8 string.
  ///
  /// Throws [ArgumentError] if [ean8] is not exactly 8 numeric digits.
  static String ean8ToItemCode(String ean8) {
    if (ean8.length != 8 || int.tryParse(ean8) == null) {
      throw ArgumentError('Expected 8-digit numeric EAN-8, got: "$ean8"');
    }
    return ean8.substring(0, 7);
  }
}
