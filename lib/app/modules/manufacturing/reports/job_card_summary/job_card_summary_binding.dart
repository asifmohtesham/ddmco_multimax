import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_controller.dart';

class JobCardSummaryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<WorkOrderProvider>(() => WorkOrderProvider(), fenix: true);
    Get.lazyPut<JobCardSummaryController>(() => JobCardSummaryController());
  }
}
