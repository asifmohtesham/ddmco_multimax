import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_ledger/stock_ledger_controller.dart';

class StockLedgerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockLedgerController>(() => StockLedgerController());
  }
}