import 'package:get/get.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

class UserAreaBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserAreaController>(() => UserAreaController());
  }
}
