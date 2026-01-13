import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class SerialBatchProvider {
  final ApiProvider _api = Get.find<ApiProvider>();

  // Fetch available Serial Numbers for an Item in a Warehouse
  Future<List<String>> getAvailableSerials(String itemCode, String warehouse) async {
    // Utilizing the generic getDocumentList from your existing provider
    final response = await _api.getDocumentList(
      'Serial No',
      fields: ['name'],
      filters: {
        'item_code': itemCode,
        'warehouse': warehouse,
        'status': 'Active', // Only fetch active serials
      },
      limit: 1000, // Fetch ample amount
    );

    if (response.statusCode == 200) {
      final List data = response.data['data'];
      return data.map((e) => e['name'] as String).toList();
    }
    return [];
  }

  // Fetch available Batches
  Future<List<Map<String, dynamic>>> getAvailableBatches(String itemCode, String warehouse) async {
    // We use getStockBalance from ApiProvider or a specific Report call
    // Here we use a direct report query similar to getBatchWiseBalance
    final response = await _api.getBatchWiseBalance(
        itemCode: itemCode,
        warehouse: warehouse,
        batchNo: null,
        fromDate: null,
        toDate: null
    );

    // *Parsing logic would go here depending on the specific report structure*
    // This is a placeholder for the logic that extracts batch names and balances
    return [];
  }

  // Create the Bundle in ERPNext
  Future<String> submitBundle(Map<String, dynamic> bundleData) async {
    // Uses the generic createDocument method
    final response = await _api.createDocument('Serial and Batch Bundle', bundleData);

    if (response.statusCode == 200) {
      return response.data['data']['name'];
    } else {
      throw Exception('Failed to create bundle: ${response.statusMessage}');
    }
  }
}