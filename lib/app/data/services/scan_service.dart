import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';

class ScanService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// [contextItemCode]: Pass this if a BottomSheet is open and we have an active item context.
  /// This enables the "short batch code" logic (concatenating EAN + short code).
  Future<ScanResult> processScan(String barcode, {String? contextItemCode}) async {
    if (barcode.isEmpty) {
      return ScanResult(type: ScanType.error, rawCode: barcode, message: "Empty barcode");
    }

    // 1. RACK DETECTION
    // Heuristic: contains hyphens and has multiple parts (e.g. WH-ZONE-RACK)
    if (barcode.contains('-') && barcode.split('-').length >= 3) {
      return ScanResult(type: ScanType.rack, rawCode: barcode, rackId: barcode);
    }

    // 2. BATCH CONTEXT LOGIC (Short Code)
    // If we are in a sheet (contextItemCode exists) and scan is simple alphanumeric (3+ chars)
    if (contextItemCode != null &&
        !barcode.contains('-') &&
        RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(barcode)) {

      // Construct the full batch ID
      final fullBatchNo = '$contextItemCode-$barcode';
      return ScanResult(
          type: ScanType.batch,
          rawCode: barcode,
          itemCode: contextItemCode,
          batchNo: fullBatchNo
      );
    }

    // 3. ITEM / FULL BATCH PARSING
    String parsedItemCode = barcode;
    String? parsedBatchNo;

    if (barcode.contains('-')) {
      // Format: {EAN}-{BatchID}
      // The scanned barcode IS the batch document name
      final parts = barcode.split('-');
      parsedItemCode = parts.first; // EAN is the first part
      parsedBatchNo = barcode;
    } else {
      // Pure EAN / Item Code
      // Logic: Item Code is EAN minus the last checksum digit if length > 7 (standard EAN8/13)
      if (barcode.length > 7 && RegExp(r'^\d+$').hasMatch(barcode)) {
        parsedItemCode = barcode.substring(0, barcode.length - 1);
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
    } catch (e) {
      return ScanResult(
          type: ScanType.error,
          rawCode: barcode,
          message: "Network Error: $e"
      );
    }
  }
}