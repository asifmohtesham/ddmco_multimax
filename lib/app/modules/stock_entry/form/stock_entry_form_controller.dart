import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/stock_entry_model.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';

class StockEntryFormController extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var stockEntry = Rx<StockEntry?>(null);

  @override
  void onInit() {
    super.onInit();
    fetchStockEntry();
  }

  Future<void> fetchStockEntry() async {
    isLoading.value = true;
    try {
      final response = await _provider.getStockEntry(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        stockEntry.value = StockEntry.fromJson(response.data['data']);
      } else {
        Get.snackbar('Error', 'Failed to fetch stock entry');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
