import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/hr/reports/employee_hours_utilization/employee_hours_utilization_controller.dart';

class EmployeeHoursUtilizationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    // Home registers this permanently; lazyPut keeps a direct route to the
    // report from crashing on the default-company lookup.
    Get.lazyPut<StorageService>(() => StorageService());
    Get.lazyPut<EmployeeHoursUtilizationController>(
      () => EmployeeHoursUtilizationController(),
    );
  }
}
