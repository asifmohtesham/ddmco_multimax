import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';

class DeliveryNoteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteController>(() => DeliveryNoteController());
  }
}