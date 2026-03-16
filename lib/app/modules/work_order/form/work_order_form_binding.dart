import 'package:get/get.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'work_order_form_controller.dart';

class WorkOrderFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WorkOrderProvider>(() => WorkOrderProvider());
    Get.lazyPut<WorkOrderFormController>(() => WorkOrderFormController());
  }
}
