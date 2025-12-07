import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/profile/user_profile_controller.dart';

class UserProfileBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<UserProfileController>(() => UserProfileController());
  }
}