import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';

class StockSheetBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockSheetController>(() => StockSheetController());
  }
}
