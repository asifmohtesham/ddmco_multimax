import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_screen.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_controller.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_screen.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_controller.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_screen.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_controller.dart';
import 'package:multimax/app/middleware/permission_middleware.dart';

class ManufacturingRoutes {
  static const String bom = '/manufacturing/bom';
  static const String workOrders = '/manufacturing/work-orders';
  static const String jobCards = '/manufacturing/job-cards';

  static List<GetPage> routes = [
    GetPage(
      name: bom,
      page: () => const BomScreen(),
      binding: BomBinding(),
      middlewares: [
        PermissionMiddleware(
          requiredPermissions: ['BOM', 'read'],
          roles: ['Manufacturing Manager', 'Manufacturing User', 'Supervisor'],
        ),
      ],
    ),
    GetPage(
      name: workOrders,
      page: () => const WorkOrderScreen(),
      binding: WorkOrderBinding(),
      middlewares: [
        PermissionMiddleware(
          requiredPermissions: ['Work Order', 'read'],
          roles: ['Manufacturing Manager', 'Manufacturing User', 'Supervisor'],
        ),
      ],
    ),
    GetPage(
      name: jobCards,
      page: () => const JobCardScreen(),
      binding: JobCardBinding(),
      middlewares: [
        PermissionMiddleware(
          requiredPermissions: ['Job Card', 'read'],
          roles: ['Manufacturing Manager', 'Manufacturing User', 'Supervisor', 'Labourer'],
        ),
      ],
    ),
  ];
}

// Bindings for dependency injection
class BomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomController>(() => BomController());
  }
}

class WorkOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WorkOrderController>(() => WorkOrderController());
  }
}

class JobCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardController>(() => JobCardController());
  }
}