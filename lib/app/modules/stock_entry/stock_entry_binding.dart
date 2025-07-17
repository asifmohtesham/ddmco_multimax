import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_controller.dart';

class StockEntryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockEntryController>(() => StockEntryController());
  }
}