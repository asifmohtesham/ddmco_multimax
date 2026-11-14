import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_ageing/stock_ageing_controller.dart';

class StockAgeingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockAgeingController>(() => StockAgeingController());
  }
}
