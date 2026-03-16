import 'package:get/get.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';

class PosUploadBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CustomerProvider>(() => CustomerProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<PosUploadController>(() => PosUploadController());
  }
}
