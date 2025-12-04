
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';
import 'package:ddmco_multimax/app/data/providers/item_provider.dart';

class ItemFormController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();
  
  // We can pass the full item object if available, or just the ID to fetch it.
  // For robustness, let's support fetching by ID.
  final String itemCode = Get.arguments['itemCode'];
  var item = Rx<Item?>(null);
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItemDetails();
  }

  Future<void> fetchItemDetails() async {
    isLoading.value = true;
    try {
      // We might need a specific method in provider to get full details if list view is partial.
      // Reusing filters for now to get single item.
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
}
