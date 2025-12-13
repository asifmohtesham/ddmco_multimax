import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/permission_service.dart';

class DocTypeGuard extends StatelessWidget {
  final String doctype;
  final Widget child;
  final Widget? fallback;
  final Widget? loading; // Added loading widget slot

  const DocTypeGuard({
    super.key,
    required this.doctype,
    required this.child,
    this.fallback,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final PermissionService service = Get.find<PermissionService>();

    return Obx(() {
      final hasAccess = service.hasReadAccess(doctype);

      // 1. Loading State
      if (hasAccess == null) {
        return loading ?? const SizedBox.shrink();
      }

      // 2. Access Granted
      if (hasAccess == true) {
        return child;
      }

      // 3. Access Denied
      return fallback ?? const SizedBox.shrink();
    });
  }
}