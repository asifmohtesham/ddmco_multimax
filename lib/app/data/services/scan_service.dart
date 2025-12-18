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

    final cleanCode = barcode.trim();

    // 1. RACK DETECTION
    // Rack codes usually have 3 parts (e.g., WH-ZONE-RACK) and don't start with SHIPMENT
    if (cleanCode.contains('-') && cleanCode.split('-').length >= 3 && !cleanCode.startsWith('SHIPMENT')) {
      return ScanResult(type: ScanType.rack, rawCode: cleanCode, rackId: cleanCode);
    }

    // 2. BATCH CONTEXT LOGIC (Suffix Extraction)
    if (contextItemCode != null) {
      String? extractedSuffix;

      // Handle "SHIPMENT-24-{BatchID}-..."
      if (cleanCode.startsWith('SHIPMENT-24-')) {
        final raw = cleanCode.substring('SHIPMENT-24-'.length);
        extractedSuffix = raw.split('-').first;
      }
      // Handle "SHIPMENT-{BatchID}-..."
      else if (cleanCode.startsWith('SHIPMENT-')) {
        final raw = cleanCode.substring('SHIPMENT-'.length);
        extractedSuffix = raw.split('-').first;
      }
      // Handle Simple Alphanumeric (3+ chars, no hyphens)
      else if (!cleanCode.contains('-') && RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(cleanCode)) {
        extractedSuffix = cleanCode;
      }

      // If valid suffix found, construct full batch: {ItemCode}-{Suffix}
      if (extractedSuffix != null && extractedSuffix.isNotEmpty) {
        final fullBatchNo = '$contextItemCode-$extractedSuffix';
        return ScanResult(
            type: ScanType.batch,
            rawCode: cleanCode,
            itemCode: contextItemCode,
            batchNo: fullBatchNo
        );
      }
    }

    // 3. STRICT ITEM & EAN8 VALIDATION
    String? derivedItemCode;
    String? parsedBatchNo;

    if (cleanCode.contains('-')) {
      // Hyphenated Case: {EAN8}-{BatchID}
      final parts = cleanCode.split('-');
      final String prefix = parts.first;

      // Validate Prefix is strict EAN-8
      if (_isValidEan8(prefix)) {
        // Discard the last digit (checksum) to derive Item Code
        derivedItemCode = prefix.substring(0, 7);
        parsedBatchNo = cleanCode;
      } else {
        return ScanResult(
            type: ScanType.error,
            rawCode: cleanCode,
            message: "Invalid Item Barcode: Prefix must be EAN-8"
        );
      }
    } else {
      // Non-Hyphenated Case: Must be strict EAN-8
      if (_isValidEan8(cleanCode)) {
        // Discard the last digit (checksum) to derive Item Code
        derivedItemCode = cleanCode.substring(0, 7);
        parsedBatchNo = null; // Pure Item Scan
      } else {
        return ScanResult(
            type: ScanType.error,
            rawCode: cleanCode,
            message: "Invalid Barcode. Please scan a valid EAN-8 Item."
        );
      }
    }

    // 4. API VERIFICATION (Only performed if validation passed)
    try {
      final response = await _apiProvider.getDocument('Item', derivedItemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final item = Item.fromJson(response.data['data']);
        return ScanResult(
          type: parsedBatchNo != null ? ScanType.batch : ScanType.item,
          rawCode: cleanCode,
          itemCode: item.itemCode,
          batchNo: parsedBatchNo,
          itemData: item,
        );
      }
      // Explicit Not Found
      return ScanResult(
          type: ScanType.error,
          rawCode: cleanCode,
          message: "Item not found: $derivedItemCode"
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return ScanResult(
            type: ScanType.error,
            rawCode: cleanCode,
            message: "Item not found in database: $derivedItemCode"
        );
      }
      return ScanResult(
          type: ScanType.error,
          rawCode: cleanCode,
          message: "Network Error: ${e.message}"
      );
    } catch (e) {
      return ScanResult(
          type: ScanType.error,
          rawCode: cleanCode,
          message: "Scan Error: $e"
      );
    }
  }

  /// strict EAN-8 validation helper
  bool _isValidEan8(String code) {
    if (code.length != 8) return false;
    if (!RegExp(r'^\d+$').hasMatch(code)) return false;

    // EAN-8 Weights: 3 1 3 1 3 1 3
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      int digit = int.parse(code[i]);
      // Alternate weights: Even indices (0, 2...) are *3, Odd indices (1, 3...) are *1
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }

    int checksum = (10 - (sum % 10)) % 10;
    int lastDigit = int.parse(code[7]);

    return checksum == lastDigit;
  }
}