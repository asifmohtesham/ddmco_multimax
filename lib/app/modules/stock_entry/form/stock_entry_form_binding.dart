import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

class StockEntryFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockEntryFormController>(
      () => StockEntryFormController(),
    );
  }
}
