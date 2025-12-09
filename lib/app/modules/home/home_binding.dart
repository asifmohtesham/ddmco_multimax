import 'package:get/get.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart'; // Added

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(DataWedgeService(), permanent: true);

    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<ToDoProvider>(() => ToDoProvider());
    Get.lazyPut<ItemProvider>(() => ItemProvider());
    Get.lazyPut<WorkOrderProvider>(() => WorkOrderProvider());
    Get.lazyPut<JobCardProvider>(() => JobCardProvider());
    Get.lazyPut<UserProvider>(() => UserProvider()); // Added

    Get.lazyPut<HomeController>(() => HomeController());
  }
}