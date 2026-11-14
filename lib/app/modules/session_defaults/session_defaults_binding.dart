import 'package:get/get.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

class SessionDefaultsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SessionDefaultsController>(() => SessionDefaultsController());
  }
}
