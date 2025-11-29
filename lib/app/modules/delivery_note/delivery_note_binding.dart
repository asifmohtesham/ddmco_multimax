import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';

class DeliveryNoteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<DeliveryNoteController>(() => DeliveryNoteController());
  }
}
