import 'package:get/get.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';

class SalesOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SalesOrderProvider>(() => SalesOrderProvider(), fenix: true);
    Get.lazyPut<UserProvider>(() => UserProvider());
    Get.lazyPut<SalesOrderController>(() => SalesOrderController());
  }
}
