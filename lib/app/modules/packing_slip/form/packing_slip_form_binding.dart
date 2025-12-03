import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

class PackingSlipFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PackingSlipFormController>(() => PackingSlipFormController());
  }
}
