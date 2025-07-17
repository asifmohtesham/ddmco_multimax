import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_controller.dart';

class PackingSlipBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PackingSlipController>(() => PackingSlipController());
  }
}