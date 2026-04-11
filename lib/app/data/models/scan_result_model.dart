import 'package:multimax/app/data/models/item_model.dart';

enum ScanType {
  item,
  batch,
  rack,

  /// Variant-group template resolved via variant_of / custom_variant_of.
  /// Exposed as a first-class type because the app is internal and
  /// controllers need to distinguish variant templates from direct items.
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

  const ScanResult({
    required this.type,
    required this.rawCode,
    this.itemCode,
    this.batchNo,
    this.rackId,
    this.itemData,
    this.candidates,
    this.message,
  });

  // ── Factory constructors (DRY: eliminate repeated inline construction) ────

  factory ScanResult.error(String rawCode, String message) => ScanResult(
        type: ScanType.error,
        rawCode: rawCode,
        message: message,
      );

  factory ScanResult.rack(String rawCode) => ScanResult(
        type: ScanType.rack,
        rawCode: rawCode,
        rackId: rawCode,
      );

  factory ScanResult.batch({
    required String rawCode,
    required String itemCode,
    required String batchNo,
  }) =>
      ScanResult(
        type: ScanType.batch,
        rawCode: rawCode,
        itemCode: itemCode,
        batchNo: batchNo,
      );

  factory ScanResult.item({
    required String rawCode,
    required Item itemData,
    String? batchNo,
  }) =>
      ScanResult(
        type: batchNo != null ? ScanType.batch : ScanType.item,
        rawCode: rawCode,
        itemCode: itemData.itemCode,
        batchNo: batchNo,
        itemData: itemData,
      );

  factory ScanResult.variantOf(String rawCode) => ScanResult(
        type: ScanType.variant_of,
        rawCode: rawCode,
        message: 'Item Variant Found',
      );

  bool get isSuccess => type != ScanType.error && type != ScanType.unknown;
}
