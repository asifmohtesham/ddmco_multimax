import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/erpnext_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Middleware to check user permissions before navigating to a route
class PermissionMiddleware extends GetMiddleware {
  final List<String> requiredPermissions;
  final List<String> roles;

  PermissionMiddleware({
    required this.requiredPermissions,
    required this.roles,
  });

  @override
  RouteSettings? redirect(String? route) {
    final erpnextProvider = Get.find<ErpnextProvider>();
    
    // Check if user is authenticated
    if (!erpnextProvider.isAuthenticated) {
      GlobalSnackbar.error(message: 'Please login to access this page');
      return const RouteSettings(name: '/login');
    }

    // Check user permissions
    if (!_hasPermission(erpnextProvider)) {
      GlobalSnackbar.error(
        message: 'You do not have permission to access this page',
      );
      return const RouteSettings(name: '/home');
    }

    return null; // Allow navigation
  }

  bool _hasPermission(ErpnextProvider provider) {
    final userRoles = provider.userRoles ?? [];
    
    // Check if user has any of the required roles
    final hasRole = roles.any((role) => userRoles.contains(role));
    
    if (!hasRole) {
      return false;
    }

    // Additional permission check for specific DocType operations
    // This would integrate with ERPNext's permission system
    // For MVP, role check is sufficient
    
    return true;
  }
}

/// Permission helper class for checking permissions throughout the app
class PermissionHelper {
  static final ErpnextProvider _provider = Get.find<ErpnextProvider>();

  /// Check if user has a specific role
  static bool hasRole(String role) {
    final userRoles = _provider.userRoles ?? [];
    return userRoles.contains(role);
  }

  /// Check if user has any of the specified roles
  static bool hasAnyRole(List<String> roles) {
    final userRoles = _provider.userRoles ?? [];
    return roles.any((role) => userRoles.contains(role));
  }

  /// Check if user has all of the specified roles
  static bool hasAllRoles(List<String> roles) {
    final userRoles = _provider.userRoles ?? [];
    return roles.every((role) => userRoles.contains(role));
  }

  /// Check if user can read a DocType
  static bool canRead(String doctype) {
    return _checkDocTypePermission(doctype, 'read');
  }

  /// Check if user can write to a DocType
  static bool canWrite(String doctype) {
    return _checkDocTypePermission(doctype, 'write');
  }

  /// Check if user can create a DocType
  static bool canCreate(String doctype) {
    return _checkDocTypePermission(doctype, 'create');
  }

  /// Check if user can delete a DocType
  static bool canDelete(String doctype) {
    return _checkDocTypePermission(doctype, 'delete');
  }

  /// Check if user can submit a DocType
  static bool canSubmit(String doctype) {
    return _checkDocTypePermission(doctype, 'submit');
  }

  static bool _checkDocTypePermission(String doctype, String permissionType) {
    // In a full implementation, this would check against ERPNext's
    // permission system via API call
    // For MVP, we'll use role-based checks
    
    final userRoles = _provider.userRoles ?? [];
    
    // Manufacturing Manager has all permissions
    if (userRoles.contains('Manufacturing Manager')) {
      return true;
    }

    // Manufacturing User has read/write for all manufacturing docs
    if (userRoles.contains('Manufacturing User')) {
      if (permissionType == 'read' || permissionType == 'write') {
        return _isManufacturingDocType(doctype);
      }
    }

    // Supervisor can read all, write Job Cards and Work Orders
    if (userRoles.contains('Supervisor')) {
      if (permissionType == 'read') {
        return _isManufacturingDocType(doctype);
      }
      if (permissionType == 'write') {
        return doctype == 'Job Card' || doctype == 'Work Order';
      }
    }

    // Labourer can only read and write Job Cards
    if (userRoles.contains('Labourer')) {
      if (doctype == 'Job Card') {
        return permissionType == 'read' || permissionType == 'write';
      }
    }

    return false;
  }

  static bool _isManufacturingDocType(String doctype) {
    return ['BOM', 'Work Order', 'Job Card', 'Workstation', 'Operation'].contains(doctype);
  }

  /// Get user's role for display
  static String getUserRole() {
    final userRoles = _provider.userRoles ?? [];
    
    if (userRoles.contains('Manufacturing Manager')) return 'Manager';
    if (userRoles.contains('Supervisor')) return 'Supervisor';
    if (userRoles.contains('Labourer')) return 'Labourer';
    if (userRoles.contains('Manufacturing User')) return 'User';
    
    return 'Unknown';
  }

  /// Check if user is a labourer (limited UI)
  static bool isLabourer() {
    return hasRole('Labourer') && !hasAnyRole(['Supervisor', 'Manufacturing Manager']);
  }

  /// Check if user is a supervisor or higher
  static bool isSupervisor() {
    return hasAnyRole(['Supervisor', 'Manufacturing Manager', 'Manufacturing User']);
  }
}