import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/permission_service.dart';

class DocTypeGuard extends StatelessWidget {
  final String doctype;

  /// The Frappe permission type to check. Defaults to `'read'`.
  /// Use `'report'` for report links (mirrors ERPNext's server enforcement).
  final String permType;

  final Widget child;
  final Widget? fallback;
  final Widget? loading;

  const DocTypeGuard({
    super.key,
    required this.doctype,
    this.permType = 'read',
    required this.child,
    this.fallback,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final PermissionService service = Get.find<PermissionService>();

    return Obx(() {
      final hasAccess = service.hasAccess(doctype, permType: permType);

      // Loading state — null only when the entry was not pre-fetched
      if (hasAccess == null) {
        return loading ?? const SizedBox.shrink();
      }

      if (hasAccess == true) return child;

      return fallback ?? const SizedBox.shrink();
    });
  }
}
