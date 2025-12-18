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
    if (cleanCode.contains('-') && cleanCode.split('-').length >= 3 && !cleanCode.startsWith('SHIPMENT')) {
      return ScanResult(type: ScanType.rack, rawCode: cleanCode, rackId: cleanCode);
    }

    // 2. BATCH CONTEXT LOGIC (Suffix Extraction)
    if (contextItemCode != null) {
      String? extractedSuffix;
      if (cleanCode.startsWith('SHIPMENT-24-')) {
        extractedSuffix = cleanCode.substring('SHIPMENT-24-'.length).split('-').first;
      } else if (cleanCode.startsWith('SHIPMENT-')) {
        extractedSuffix = cleanCode.substring('SHIPMENT-'.length).split('-').first;
      } else if (!cleanCode.contains('-') && RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(cleanCode)) {
        extractedSuffix = cleanCode;
      }

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

    // 3. ATTEMPT ITEM RESOLUTION (Strict EAN-8)
    String? derivedItemCode;
    String? parsedBatchNo;
    bool isEan8Candidate = false;

    if (cleanCode.contains('-')) {
      // Hyphenated Case: {EAN8}-{BatchID}
      final parts = cleanCode.split('-');
      final String prefix = parts.first;
      if (_isValidEan8(prefix)) {
        derivedItemCode = prefix.substring(0, 7);
        parsedBatchNo = cleanCode;
        isEan8Candidate = true;
      }
    } else {
      // Non-Hyphenated Case: Strict EAN-8
      if (_isValidEan8(cleanCode)) {
        derivedItemCode = cleanCode.substring(0, 7);
        parsedBatchNo = null;
        isEan8Candidate = true;
      }
    }

    // If it looks like a valid EAN-8 Item, try to fetch it directly
    if (isEan8Candidate && derivedItemCode != null) {
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
      } on DioException catch (e) {
        // If network error (not 404), return error.
        // If 404, we intentionally fall through to the Variant Check.
        if (e.response?.statusCode != 404) {
          return ScanResult(
              type: ScanType.error,
              rawCode: cleanCode,
              message: "Network Error: ${e.message}"
          );
        }
      } catch (e) {
        return ScanResult(type: ScanType.error, rawCode: cleanCode, message: "Scan Error: $e");
      }
    }

    // 4. VARIANT OF DETECTION (Fallback)
    // If not EAN-8, or EAN-8 Item not found, check if it matches a 'variant_of' group.
    try {
      final response = await _apiProvider.getDocumentList(
          'Item',
          filters: {'variant_of': ['like', '%$cleanCode%']},
          limit: 1,
          fields: ['name']
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List data = response.data['data'];
        if (data.isNotEmpty) {
          // Found items that are variants of this code
          // Note: Ensure ScanType.variant_of is added to your ScanResultModel enum
          return ScanResult(
              type: ScanType.variant_of,
              rawCode: cleanCode,
              message: "Variant Group Found"
          );
        }
      }
    } catch (e) {
      // Ignore errors here and return generic error below
    }

    // 5. FINAL ERROR
    return ScanResult(
        type: ScanType.error,
        rawCode: cleanCode,
        message: "Item not found or invalid barcode"
    );
  }

  /// strict EAN-8 validation helper
  bool _isValidEan8(String code) {
    if (code.length != 8) return false;
    if (!RegExp(r'^\d+$').hasMatch(code)) return false;

    // EAN-8 Weights: 3 1 3 1 3 1 3
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      int digit = int.parse(code[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }

    int checksum = (10 - (sum % 10)) % 10;
    int lastDigit = int.parse(code[7]);

    return checksum == lastDigit;
  }
}