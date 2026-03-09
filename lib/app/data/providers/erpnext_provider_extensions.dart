// ERPNext Provider Extensions for Manufacturing Module
// Add these methods to your existing ErpnextProvider class

import 'package:get/get.dart';

/// Extension methods needed for Manufacturing module
/// Add these to your existing ErpnextProvider class
/// 
/// If these methods don't exist, implement them as shown below

abstract class ErpnextProviderExtensions {
  /// Get list of documents with filters
  /// 
  /// Example:
  /// ```dart
  /// await provider.getListWithFilters(
  ///   doctype: 'Work Order',
  ///   fields: ['name', 'status', 'qty'],
  ///   filters: {'status': 'In Process'},
  ///   orderBy: 'modified desc',
  ///   limit: 50,
  /// );
  /// ```
  Future<Map<String, dynamic>?> getListWithFilters({
    required String doctype,
    List<String>? fields,
    Map<String, dynamic>? filters,
    String? orderBy,
    int? limit,
  });

  /// Get single document by name
  /// 
  /// Example:
  /// ```dart
  /// await provider.getDoc(
  ///   doctype: 'Job Card',
  ///   name: 'JC-2024-00123',
  /// );
  /// ```
  Future<Map<String, dynamic>?> getDoc({
    required String doctype,
    required String name,
  });

  /// Update document
  /// 
  /// Example:
  /// ```dart
  /// await provider.updateDoc(
  ///   doctype: 'Job Card',
  ///   name: 'JC-2024-00123',
  ///   data: {'status': 'Completed'},
  /// );
  /// ```
  Future<Map<String, dynamic>?> updateDoc({
    required String doctype,
    required String name,
    required Map<String, dynamic> data,
  });

  /// Run DocType method
  /// 
  /// Example:
  /// ```dart
  /// await provider.runDocMethod(
  ///   doctype: 'Job Card',
  ///   name: 'JC-2024-00123',
  ///   method: 'start_timer',
  /// );
  /// ```
  Future<Map<String, dynamic>?> runDocMethod({
    required String doctype,
    required String name,
    required String method,
    Map<String, dynamic>? args,
  });

  /// Check if user is authenticated
  bool get isAuthenticated;

  /// Get user roles
  List<String>? get userRoles;
}

/// IMPLEMENTATION EXAMPLE
/// Copy this to your ErpnextProvider class and modify as needed

class ErpnextProviderImplementationExample {
  // Add these properties to your ErpnextProvider
  bool _isAuthenticated = false;
  List<String>? _userRoles;

  bool get isAuthenticated => _isAuthenticated;
  List<String>? get userRoles => _userRoles;

  // Example implementation of getListWithFilters
  Future<Map<String, dynamic>?> getListWithFilters({
    required String doctype,
    List<String>? fields,
    Map<String, dynamic>? filters,
    String? orderBy,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (fields != null && fields.isNotEmpty) {
        queryParams['fields'] = fields;
      }

      if (filters != null && filters.isNotEmpty) {
        queryParams['filters'] = filters;
      }

      if (orderBy != null) {
        queryParams['order_by'] = orderBy;
      }

      if (limit != null) {
        queryParams['limit_page_length'] = limit;
      }

      // Use your HTTP client (dio, http, etc.)
      final response = await httpClient.get(
        '/api/resource/$doctype',
        queryParameters: queryParams,
      );

      return response.data;
    } catch (e) {
      print('Error fetching list: $e');
      return null;
    }
  }

  // Example implementation of getDoc
  Future<Map<String, dynamic>?> getDoc({
    required String doctype,
    required String name,
  }) async {
    try {
      final response = await httpClient.get(
        '/api/resource/$doctype/$name',
      );

      return response.data;
    } catch (e) {
      print('Error fetching doc: $e');
      return null;
    }
  }

  // Example implementation of updateDoc
  Future<Map<String, dynamic>?> updateDoc({
    required String doctype,
    required String name,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await httpClient.put(
        '/api/resource/$doctype/$name',
        data: data,
      );

      return response.data;
    } catch (e) {
      print('Error updating doc: $e');
      return null;
    }
  }

  // Example implementation of runDocMethod
  Future<Map<String, dynamic>?> runDocMethod({
    required String doctype,
    required String name,
    required String method,
    Map<String, dynamic>? args,
  }) async {
    try {
      final response = await httpClient.post(
        '/api/method/frappe.client.run_doc_method',
        data: {
          'dt': doctype,
          'dn': name,
          'method': method,
          'args': args ?? {},
        },
      );

      return response.data;
    } catch (e) {
      print('Error running doc method: $e');
      return null;
    }
  }

  // Fetch and cache user roles after login
  Future<void> fetchUserRoles() async {
    try {
      final response = await httpClient.get(
        '/api/method/frappe.core.doctype.user.user.get_roles',
      );

      if (response.data != null && response.data['message'] != null) {
        _userRoles = List<String>.from(response.data['message']);
      }
    } catch (e) {
      print('Error fetching user roles: $e');
    }
  }
}