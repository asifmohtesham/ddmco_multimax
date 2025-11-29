import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:ddmco_multimax/app/data/providers/stock_entry_provider.dart';

class StockEntryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockEntryProvider>(() => StockEntryProvider());
    Get.lazyPut<StockEntryController>(() => StockEntryController());
  }
}
