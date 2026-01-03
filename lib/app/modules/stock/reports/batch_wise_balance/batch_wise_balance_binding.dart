import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/batch_wise_balance/batch_wise_balance_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

class BatchWiseBalanceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BatchWiseBalanceController>(() => BatchWiseBalanceController());
  }
}