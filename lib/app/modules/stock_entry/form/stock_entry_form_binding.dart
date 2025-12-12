import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class StockEntryFormBinding extends Bindings {
  @override
  void dependencies() {
    // Inject dependencies required by StockEntryFormController
    Get.lazyPut<StockEntryProvider>(() => StockEntryProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<StorageService>(() => StorageService());

    // Inject the Controller
    Get.lazyPut<StockEntryFormController>(() => StockEntryFormController());
  }
}