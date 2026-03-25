import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

class PackingSlipFormBinding extends Bindings {
  @override
  void dependencies() {
    // -------------------------------------------------------------------------
    // Permanent singletons (registered in HomeBinding with permanent:true).
    // Declaring them here with fenix:true ensures Get.find<>() never throws
    // if GetX marks the instance inactive between navigation events or on
    // a hot-restart deep-link into this screen.
    // -------------------------------------------------------------------------
    Get.lazyPut<DataWedgeService>(() => DataWedgeService(), fenix: true);

    // -------------------------------------------------------------------------
    // Providers shared with other screens (also registered in HomeBinding).
    // fenix:true keeps them alive across repeated push/pop of this route.
    // -------------------------------------------------------------------------
    Get.lazyPut<PackingSlipProvider>(() => PackingSlipProvider(), fenix: true);
    Get.lazyPut<DeliveryNoteProvider>(() => DeliveryNoteProvider(), fenix: true);
    Get.lazyPut<PosUploadProvider>(() => PosUploadProvider(),   fenix: true);
    Get.lazyPut<ApiProvider>(() => ApiProvider(),               fenix: true);

    // -------------------------------------------------------------------------
    // Screen-local controller — disposed automatically when the route is popped.
    // -------------------------------------------------------------------------
    Get.lazyPut<PackingSlipFormController>(() => PackingSlipFormController());
  }
}
