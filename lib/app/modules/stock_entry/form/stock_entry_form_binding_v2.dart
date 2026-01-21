import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller_v2.dart';

class StockEntryFormBindingV2 extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockEntryFormControllerV2>(
          () => StockEntryFormControllerV2(),
    );
  }
}