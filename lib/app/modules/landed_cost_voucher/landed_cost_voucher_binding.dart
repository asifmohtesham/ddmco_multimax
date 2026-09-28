import 'package:get/get.dart';
import 'package:multimax/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';

class LandedCostVoucherBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LandedCostVoucherProvider>(() => LandedCostVoucherProvider());
    Get.lazyPut<LandedCostVoucherController>(
      () => LandedCostVoucherController(),
    );
  }
}
