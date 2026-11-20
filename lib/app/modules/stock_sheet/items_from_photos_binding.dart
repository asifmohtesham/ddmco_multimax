import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';

class StockSheetBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockSheetController>(() => StockSheetController());
  }
}
