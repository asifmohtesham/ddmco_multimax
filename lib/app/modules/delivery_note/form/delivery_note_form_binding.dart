import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_controller.dart';

class DeliveryNoteFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteFormController>(
      () => DeliveryNoteFormController(),
    );
  }
}
