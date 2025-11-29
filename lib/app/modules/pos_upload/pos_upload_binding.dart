import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/pos_upload_controller.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';

class PosUploadBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<PosUploadController>(() => PosUploadController());
  }
}
