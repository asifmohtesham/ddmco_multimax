import 'package:get/get.dart';
import 'package:dio/dio.dart'; // Added for DioException
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
    if (barcode.contains('-') && barcode.split('-').length >= 3 && !barcode.startsWith('SHIPMENT')) {
      return ScanResult(type: ScanType.rack, rawCode: barcode, rackId: barcode);
    }

    // 2. BATCH CONTEXT LOGIC (Short Code / Prefix Logic)
    if (contextItemCode != null) {
      String? extractedSuffix;

      // Handle "SHIPMENT-24-{ID}" (Check longer prefix first)
      if (barcode.startsWith('SHIPMENT-24-')) {
        extractedSuffix = barcode.substring('SHIPMENT-24-'.length, barcode.length - 2);
      }
      // Handle "SHIPMENT-{ID}"
      else if (barcode.startsWith('SHIPMENT-')) {
        extractedSuffix = barcode.substring('SHIPMENT-'.length);
      }
      // Handle Simple Alphanumeric (3+ chars, no hyphens)
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

    // 3. ITEM / FULL BATCH PARSING
    String parsedItemCode = barcode;
    String? parsedBatchNo;

    if (barcode.contains('-')) {
      // Format: {EAN}-{BatchID} -> The scanned barcode IS the batch document name
      final parts = barcode.split('-');
      parsedItemCode = parts.first.substring(0, parts.first.length - 1);
      parsedBatchNo = barcode;
    } else {
      // Pure EAN / Item Code logic
      if (barcode.length > 7 && RegExp(r'^\d+$').hasMatch(barcode)) {
        parsedItemCode = barcode.substring(0, barcode.length - 1); // Strip checksum
      } else {
        parsedItemCode = barcode;
      }
    }

    // 4. API VERIFICATION
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
      } else {
        return ScanResult(
            type: ScanType.error,
            rawCode: barcode,
            message: "Item not found: $parsedItemCode"
        );
      }
    } on DioException catch (e) {
      // Gracefully handle 404 from API
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