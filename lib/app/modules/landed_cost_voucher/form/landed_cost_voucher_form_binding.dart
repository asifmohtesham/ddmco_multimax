import 'package:get/get.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';

class LandedCostVoucherFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LandedCostVoucherProvider>(() => LandedCostVoucherProvider());
    Get.lazyPut<LandedCostVoucherFormController>(
      () => LandedCostVoucherFormController(),
    );
  }
}
