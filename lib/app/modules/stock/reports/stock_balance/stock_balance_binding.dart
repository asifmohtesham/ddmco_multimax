import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

class StockBalanceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockBalanceController>(() => StockBalanceController());
  }
}