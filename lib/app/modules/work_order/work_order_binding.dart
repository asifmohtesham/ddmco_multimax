import 'package:get/get.dart';
import 'package:multimax/app/modules/work_order/work_order_controller.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';

class WorkOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WorkOrderProvider>(() => WorkOrderProvider());
    Get.lazyPut<WorkOrderController>(() => WorkOrderController());
  }
}