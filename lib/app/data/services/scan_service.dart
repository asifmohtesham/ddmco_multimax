import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

class ScanService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<ScanResult> processScan(String barcode, {String? contextItemCode}) async {
    if (barcode.isEmpty) {
      return ScanResult(type: ScanType.error, rawCode: barcode, message: "Empty barcode");
    }

    // 1. RACK DETECTION
    // Rack codes usually have 3 parts (e.g., WH-ZONE-RACK) and don't start with SHIPMENT
    if (barcode.contains('-') && barcode.split('-').length >= 3 && !barcode.startsWith('SHIPMENT')) {
      return ScanResult(type: ScanType.rack, rawCode: barcode, rackId: barcode);
    }

    // 2. BATCH CONTEXT LOGIC (Suffix Extraction)
    if (contextItemCode != null) {
      String? extractedSuffix;

      // Handle "SHIPMENT-24-{BatchID}-..." (e.g. SHIPMENT-24-7M6-1 -> 7M6)
      if (barcode.startsWith('SHIPMENT-24-')) {
        final raw = barcode.substring('SHIPMENT-24-'.length);
        // Take only the part before the next hyphen
        extractedSuffix = raw.split('-').first;
      }
      // Handle "SHIPMENT-{BatchID}-..." (e.g. SHIPMENT-7M6 -> 7M6)
      else if (barcode.startsWith('SHIPMENT-')) {
        final raw = barcode.substring('SHIPMENT-'.length);
        extractedSuffix = raw.split('-').first;
      }
      // Handle Simple Alphanumeric (3+ chars, no hyphens, e.g. 7M6)
      else if (!barcode.contains('-') && RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(barcode)) {
        extractedSuffix = barcode;
      }

      // If valid suffix found, construct full batch: {ItemCode}-{Suffix}
      if (extractedSuffix != null && extractedSuffix.isNotEmpty) {
        final fullBatchNo = '$contextItemCode-$extractedSuffix';
        return ScanResult(
            type: ScanType.batch,
            rawCode: barcode,
            itemCode: contextItemCode,
            batchNo: fullBatchNo
        );
      }
    }

    // 3. ITEM / FULL BATCH PARSING (Main Context)
    String parsedItemCode = barcode;
    String? parsedBatchNo;

    if (barcode.contains('-')) {
      // Format: {EAN}-{BatchID} -> The scanned barcode IS the batch document name
      final parts = barcode.split('-');
      parsedItemCode = parts.first;
      parsedBatchNo = barcode;
    } else {
      // Pure EAN / Item Code logic
      // Strip checksum if EAN (digits > 7)
      if (barcode.length > 7 && RegExp(r'^\d+$').hasMatch(barcode)) {
        parsedItemCode = barcode.substring(0, barcode.length - 1);
      } else {
        parsedItemCode = barcode;
      }
    }

    // 4. API VERIFICATION & SEARCH
    try {
      // Step A: Try Exact Match
      try {
        final response = await _apiProvider.getDocument('Item', parsedItemCode);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final item = Item.fromJson(response.data['data']);
          return ScanResult(
            type: parsedBatchNo != null ? ScanType.batch : ScanType.item,
            rawCode: barcode,
            itemCode: item.itemCode,
            batchNo: parsedBatchNo,
            itemData: item,
          );
        }
      } catch (e) {
        // Ignore initial lookup failure, proceed to search
      }

      // Step B: Fallback Search (Variant Of OR Item Code like)
      final futures = <Future<Response>>[];
      futures.add(_apiProvider.getDocumentList('Item', filters: {'item_code': ['like', '%$barcode%']}, limit: 10));
      futures.add(_apiProvider.getDocumentList('Item', filters: {'variant_of': ['like', '%$barcode%']}, limit: 10));

      final results = await Future.wait(futures);
      final Map<String, Item> mergedItems = {};

      for (var response in results) {
        if (response.statusCode == 200 && response.data['data'] != null) {
          for (var json in response.data['data']) {
            final item = Item.fromJson(json);
            mergedItems[item.itemCode] = item;
          }
        }
      }

      if (mergedItems.isNotEmpty) {
        final candidates = mergedItems.values.toList();
        return ScanResult(
          type: ScanType.multiple,
          rawCode: barcode,
          candidates: candidates,
        );
      }

      return ScanResult(
          type: ScanType.error,
          rawCode: barcode,
          message: "Item not found"
      );

    } on DioException catch (e) {
      // 1. Gracefully handle 404
      if (e.response?.statusCode == 404) {
        return ScanResult(
            type: ScanType.error,
            rawCode: barcode,
            message: "Item not found in database"
        );
      }
      return ScanResult(
          type: ScanType.error,
          rawCode: barcode,
          message: "Network Error: ${e.message}"
      );
    } catch (e) {
      return ScanResult(
          type: ScanType.error,
          rawCode: barcode,
          message: "Error: $e"
      );
    }
  }
}