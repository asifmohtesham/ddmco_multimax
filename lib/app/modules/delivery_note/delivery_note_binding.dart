import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart'; // Import PosUploadProvider

class DeliveryNoteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    // Inject PosUploadProvider as it's needed by DeliveryNoteController
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider()); 
    Get.lazyPut<DeliveryNoteController>(() => DeliveryNoteController());
  }
}
