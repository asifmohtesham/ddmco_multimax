import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';

class JobCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardProvider>(() => JobCardProvider());
    Get.lazyPut<JobCardController>(() => JobCardController());
  }
}