import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/permission_service.dart';

class DocTypeGuard extends StatelessWidget {
  final String doctype;
  final Widget child;
  final Widget? fallback;

  const DocTypeGuard({
    super.key,
    required this.doctype,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final PermissionService service = Get.find<PermissionService>();

    return Obx(() {
      final hasAccess = service.hasReadAccess(doctype);

      // If null (loading) or false (denied), show fallback or shrink
      if (hasAccess == true) {
        return child;
      }

      // Optional: You could show a loading skeleton if hasAccess is null
      // But for menus, it's usually cleaner to hide until ready.
      return fallback ?? const SizedBox.shrink();
    });
  }
}