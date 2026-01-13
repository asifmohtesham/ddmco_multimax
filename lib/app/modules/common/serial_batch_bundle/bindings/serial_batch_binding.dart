import 'package:get/get.dart';
import 'package:multimax/app/modules/common/serial_batch_bundle/controllers/serial_batch_bundle_controller.dart';

class SerialBatchBundleBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SerialBatchBundleController>(() => SerialBatchBundleController());
  }
}