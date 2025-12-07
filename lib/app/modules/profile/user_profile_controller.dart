import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

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
        Get.snackbar('Success', 'Mobile number updated successfully', backgroundColor: Colors.green, colorText: Colors.white);
        refreshProfile();
      } else {
        Get.snackbar('Error', 'Failed to update mobile number', backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar('Error', 'Update failed: $e', backgroundColor: Colors.red, colorText: Colors.white);
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
        Get.snackbar('Success', 'Password changed successfully', backgroundColor: Colors.green, colorText: Colors.white);
      } else {
        Get.snackbar('Error', 'Failed to change password', backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      Get.snackbar('Error', 'Change password failed: ${e.toString()}', backgroundColor: Colors.red, colorText: Colors.white);
    } finally {
      isUpdating.value = false;
    }
  }
}