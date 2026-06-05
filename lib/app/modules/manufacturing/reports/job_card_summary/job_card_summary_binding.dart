import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/job_card_summary/job_card_summary_controller.dart';

class JobCardSummaryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<JobCardSummaryController>(() => JobCardSummaryController());
  }
}
