import 'package:get/get.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';

class PackingSlipBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider());
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider());
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider());
    Get.lazyPut<PackingSlipController>(() => PackingSlipController());
  }
}