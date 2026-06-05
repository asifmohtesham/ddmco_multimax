class ImageScanResult {
  final String itemCode;
  final String? batchNo;

  const ImageScanResult({required this.itemCode, this.batchNo});

  @override
  bool operator ==(Object other) =>
      other is ImageScanResult &&
      other.itemCode == itemCode &&
      other.batchNo == batchNo;

  @override
  int get hashCode => Object.hash(itemCode, batchNo);
}
