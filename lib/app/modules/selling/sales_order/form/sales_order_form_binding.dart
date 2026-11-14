import 'package:get/get.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_form_controller.dart';

class SalesOrderFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SalesOrderProvider>(() => SalesOrderProvider(), fenix: true);
    Get.lazyPut<SalesOrderFormController>(() => SalesOrderFormController());
  }
}
