import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';

class PackingSlipBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider());
    Get.lazyPut<PackingSlipController>(() => PackingSlipController());
  }
}
