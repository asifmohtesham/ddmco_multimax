import 'package:get/get.dart';
import 'package:multimax/app/modules/job_card/job_card_controller.dart';
import 'package:multimax/app/modules/job_card/job_card_form_controller.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';

/// Binding for the Job Card list screen.
class JobCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardProvider>(() => JobCardProvider());
    Get.lazyPut<JobCardController>(() => JobCardController());
  }
}

/// Binding for the Job Card form / detail screen.
///
/// [JobCardProvider] is registered with [permanent: false] so it is
/// cleaned up when the route is popped. If the list binding already
/// put the provider it will be reused (Get.lazyPut is idempotent when
/// the tag is the same).
class JobCardFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardProvider>(() => JobCardProvider());
    Get.lazyPut<JobCardFormController>(() => JobCardFormController());
  }
}
