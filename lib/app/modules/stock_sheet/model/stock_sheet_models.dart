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
