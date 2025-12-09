import 'package:get/get.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

class PosUploadFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosUploadFormController>(
      () => PosUploadFormController(),
    );
  }
}
