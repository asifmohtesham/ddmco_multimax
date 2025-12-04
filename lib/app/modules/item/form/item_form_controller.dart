
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';
import 'package:ddmco_multimax/app/data/providers/item_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class ItemFormController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  
  final String itemCode = Get.arguments['itemCode'];
  var item = Rx<Item?>(null);
  var isLoading = true.obs;
  
  var attachments = <Map<String, dynamic>>[].obs;
  var stockLevels = <WarehouseStock>[].obs;
  var isLoadingStock = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItemDetails();
    fetchAttachments();
    fetchStockLevels();
  }

  Future<void> fetchItemDetails() async {
    isLoading.value = true;
    try {
      final response = await _provider.getItems(limit: 1, filters: {'item_code': itemCode});
      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        item.value = Item.fromJson(response.data['data'][0]);
      } else {
        Get.snackbar('Error', 'Item not found');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchAttachments() async {
    try {
      final response = await _apiProvider.getDocumentList('File', filters: {
        'attached_to_doctype': 'Item',
        'attached_to_name': itemCode,
      }, fields: ['file_name', 'file_url', 'is_private']);
      
      if (response.statusCode == 200 && response.data['data'] != null) {
        attachments.value = List<Map<String, dynamic>>.from(response.data['data']);
      }
    } catch (e) {
      print('Error fetching attachments: $e');
    }
  }

  Future<void> fetchStockLevels() async {
    isLoadingStock.value = true;
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        // Handle the map based JSON from report
        stockLevels.value = data.map((json) => WarehouseStock.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching stock levels: $e');
    } finally {
      isLoadingStock.value = false;
    }
  }
}
