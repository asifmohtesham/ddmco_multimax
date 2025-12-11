import 'package:multimax/app/data/models/item_model.dart';

enum ScanType { item, batch, rack, unknown, error, multiple }

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

  bool get isSuccess => type != ScanType.error && type != ScanType.unknown;
}