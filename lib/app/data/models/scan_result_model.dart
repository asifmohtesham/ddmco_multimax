import 'package:multimax/app/data/models/item_model.dart';

enum ScanType { item, batch, rack, unknown, error }

class ScanResult {
  final ScanType type;
  final String rawCode;

  // Parsed Data
  final String? itemCode;
  final String? batchNo;
  final String? rackId;

  // Enriched Data (from API)
  final Item? itemData;

  // Error Info
  final String? message;

  ScanResult({
    required this.type,
    required this.rawCode,
    this.itemCode,
    this.batchNo,
    this.rackId,
    this.itemData,
    this.message,
  });

  bool get isSuccess => type != ScanType.error && type != ScanType.unknown;
}