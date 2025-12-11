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
    if (barcode.contains('-') && barcode.split('-').length >= 3 && !barcode.startsWith('SHIPMENT')) {
      return ScanResult(type: ScanType.rack, rawCode: barcode, rackId: barcode);
    }

    // 2. BATCH CONTEXT LOGIC
    if (contextItemCode != null) {
      String? extractedSuffix;
      if (barcode.startsWith('SHIPMENT-24-')) {
        extractedSuffix = barcode.substring('SHIPMENT-24-'.length);
      } else if (barcode.startsWith('SHIPMENT-')) {
        extractedSuffix = barcode.substring('SHIPMENT-'.length);
      } else if (!barcode.contains('-') && RegExp(r'^[a-zA-Z0-9]{3,}$').hasMatch(barcode)) {
        extractedSuffix = barcode;
      }

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

    // 3. ITEM PARSING
    String parsedItemCode = barcode;
    String? parsedBatchNo;

    if (barcode.contains('-')) {
      final parts = barcode.split('-');
      parsedItemCode = parts.first;
      parsedBatchNo = barcode;
    } else {
      if (barcode.length > 7 && RegExp(r'^\d+$').hasMatch(barcode)) {
        parsedItemCode = barcode.substring(0, barcode.length - 1);
      } else {
        parsedItemCode = barcode;
      }
    }

    // 4. API VERIFICATION & SEARCH
    try {
      // Step A: Try Exact Match (Direct Scan)
      // If the user scanned a specific barcode, we assume they want THAT item directly.
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
        // Ignore 404 here, fall through to search
      }

      // Step B: Fallback Search (Variant Of OR Item Code like)
      // This path is for partial searches or "Variant Of" lookups.
      // We always return 'multiple' type here to force the catalogue view.

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
        // UPDATED: Always return ScanType.multiple for search results to show the list/catalogue
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
      if (e.response?.statusCode == 404) {
        return ScanResult(type: ScanType.error, rawCode: barcode, message: "Item not found in database");
      }
      return ScanResult(type: ScanType.error, rawCode: barcode, message: "Network Error: ${e.message}");
    } catch (e) {
      return ScanResult(type: ScanType.error, rawCode: barcode, message: "Error: $e");
    }
  }
}