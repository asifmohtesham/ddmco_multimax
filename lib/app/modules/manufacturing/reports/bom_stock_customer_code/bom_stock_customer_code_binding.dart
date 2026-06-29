import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

class BomStockCustomerCodeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<BomStockCustomerCodeController>(
        () => BomStockCustomerCodeController());
  }
}
