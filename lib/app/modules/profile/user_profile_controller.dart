import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class UserProfileController extends GetxController {
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Expose current user reactively
  Rx<User?> get user => _authController.currentUser;

  var isLoading = false.obs;
  var isUpdating = false.obs;

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

  // --- Mobile Number Update ---

  String? validateMobileNumber(String? value) {
    if (value == null || value.isEmpty) return 'Mobile number is required';

    // AE Regex: Starts with +971 or 971, followed by 5x (9 digits total usually)
    // +971501234567
    final aeRegex = RegExp(r'^(?:\+971|971)(5[0-9])\d{7}$');

    // IN Regex: Starts with +91 or 91, followed by 6-9 and 9 digits
    final inRegex = RegExp(r'^(?:\+91|91)[6-9]\d{9}$');

    if (!aeRegex.hasMatch(value) && !inRegex.hasMatch(value)) {
      return 'Invalid number. Must be a valid UAE (+971...) or India (+91...) number.';
    }
    return null;
  }

  Future<void> updateMobileNumber(String newNumber) async {
    if (user.value == null) return;

    isUpdating.value = true;
    try {
      final response = await _apiProvider.updateDocument('User', user.value!.id, {'mobile_no': newNumber});
      if (response.statusCode == 200) {
        Get.back(); // Close dialog
        GlobalSnackbar.success(message: 'Mobile number updated successfully');
        refreshProfile();
      } else {
        GlobalSnackbar.error(message: 'Failed to update mobile number');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Update failed: $e');
    } finally {
      isUpdating.value = false;
    }
  }

  // --- Password Change ---

  Future<void> changePassword(String oldPassword, String newPassword) async {
    isUpdating.value = true;
    try {
      final response = await _apiProvider.changePassword(oldPassword, newPassword);
      if (response.statusCode == 200) {
        Get.back(); // Close dialog
        GlobalSnackbar.success(message: 'Password changed successfully');
      } else {
        GlobalSnackbar.error(message: 'Failed to change password');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Change password failed: ${e.toString()}');
    } finally {
      isUpdating.value = false;
    }
  }
}