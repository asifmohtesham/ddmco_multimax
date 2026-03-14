import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_controller.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';

class DeliveryNoteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<UserProvider>(() => UserProvider());
    Get.lazyPut<WarehouseProvider>(() => WarehouseProvider());
    Get.lazyPut<DeliveryNoteController>(() => DeliveryNoteController());
  }
}
