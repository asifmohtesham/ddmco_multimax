import 'package:get/get.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/todo_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // Core Services - initialized permanently
    Get.put(DataWedgeService(), permanent: true);
    Get.put(ScanService(), permanent: true);
    Get.put(StorageService(), permanent: true); // Changed from lazyPut to put (permanent)

    Get.put(PermissionService());

    // Providers
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<ToDoProvider>(() => ToDoProvider());
    Get.lazyPut<ItemProvider>(() => ItemProvider());
    Get.lazyPut<WorkOrderProvider>(() => WorkOrderProvider());
    Get.lazyPut<JobCardProvider>(() => JobCardProvider());
    Get.lazyPut<UserProvider>(() => UserProvider());
    Get.lazyPut<StockEntryProvider>(() => StockEntryProvider());

    // Controller
    Get.lazyPut<HomeController>(() => HomeController());
  }
}