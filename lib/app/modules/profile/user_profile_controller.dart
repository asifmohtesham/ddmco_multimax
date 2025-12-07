import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/data/models/user_model.dart';

class UserProfileController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();

  // Expose current user reactively
  Rx<User?> get user => _authController.currentUser;

  var isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    refreshProfile();
  }

  Future<void> refreshProfile() async {
    isLoading.value = true;
    await _authController.fetchUserDetails();
    isLoading.value = false;
  }

  void logout() {
    _authController.logoutUser();
  }
}