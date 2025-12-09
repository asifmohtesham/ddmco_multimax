import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';

class PackingSlipFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PackingSlipFormController>(() => PackingSlipFormController());
  }
}
