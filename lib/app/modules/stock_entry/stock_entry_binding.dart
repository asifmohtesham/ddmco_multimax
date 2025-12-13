import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';

class StockEntryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockEntryProvider>(() => StockEntryProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<UserProvider>(() => UserProvider()); // Added
    Get.lazyPut<StockEntryController>(() => StockEntryController());
  }
}