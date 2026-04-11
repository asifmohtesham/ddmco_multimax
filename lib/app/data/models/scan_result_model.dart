import 'package:multimax/app/data/models/item_model.dart';

enum ScanType {
  item,
  batch,
  rack,

  /// Variant-group template resolved via variant_of / custom_variant_of.
  /// Not triggered by a physical barcode today — used for manual/typed
  /// template codes and reserved for future variant-label printing.
  variant_of,

  multiple,
  unknown,
  error,
}

class ScanResult {
  final ScanType type;
  final String rawCode;

  // Parsed Data
  final String? itemCode;
  final String? batchNo;
  final String? rackId;

  // Enriched Data
  final Item? itemData;
  final List<Item>? candidates; // For multiple search results

  // Error Info
  final String? message;

  ScanResult({
    required this.type,
    required this.rawCode,
    this.itemCode,
    this.batchNo,
    this.rackId,
    this.itemData,
    this.candidates,
    this.message,
  });

  factory ScanResult.variantOf(String rawCode) => ScanResult(
    type: ScanType.variant_of,
    rawCode: rawCode,
    message: 'Item Variant Found',
  );

  bool get isSuccess => type != ScanType.error && type != ScanType.unknown;
}