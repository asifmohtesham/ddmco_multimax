import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

class RoleGuard extends StatelessWidget {
  final List<String> roles;
  final Widget child;
  final Widget? fallback;

  const RoleGuard({
    super.key,
    required this.roles,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final AuthenticationController authController = Get.find<AuthenticationController>();

    return Obx(() {
      if (authController.hasAnyRole(roles)) {
        return child;
      }
      return fallback ?? const SizedBox.shrink();
    });
  }
}