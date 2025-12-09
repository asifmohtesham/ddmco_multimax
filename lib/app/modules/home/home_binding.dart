import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';
import 'package:ddmco_multimax/app/data/providers/todo_provider.dart';
import 'package:ddmco_multimax/app/data/providers/item_provider.dart';
import 'package:ddmco_multimax/app/data/services/data_wedge_service.dart'; // Added

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(DataWedgeService(), permanent: true); // Initialize Global Service here

    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<ToDoProvider>(() => ToDoProvider());
    Get.lazyPut<ItemProvider>(() => ItemProvider());
    Get.lazyPut<HomeController>(() => HomeController());
  }
}