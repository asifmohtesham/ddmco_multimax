import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_controller.dart';

class JobCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardController>(
      () => JobCardController(),
    );
  }
}