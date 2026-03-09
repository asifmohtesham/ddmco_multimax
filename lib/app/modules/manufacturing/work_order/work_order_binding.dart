import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_controller.dart';

class WorkOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WorkOrderController>(
      () => WorkOrderController(),
    );
  }
}