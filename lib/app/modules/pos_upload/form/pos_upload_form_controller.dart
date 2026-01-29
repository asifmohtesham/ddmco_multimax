import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart'; // Import API Provider
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';

class PosUploadFormController extends GetxController with OptimisticLockingMixin {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var posUpload = Rx<PosUpload?>(null);

  // State for search and filtering
  var searchQuery = ''.obs;
  var filteredItems = <PosUploadItem>[].obs;

  // --- Dynamic Permissions State ---
  // Maps field_name to its permlevel (e.g., 'total_amount' -> 1)
  final Map<String, int> _fieldLevels = {};

  // Maps permlevel to list of Roles with Write access (e.g., 1 -> ['Accounts Manager'])
  final Map<int, Set<String>> _levelWriteRoles = {};

  var permissionsLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadData();
  }

  Future<void> _loadData() async {
    isLoading.value = true;
    await Future.wait([
      fetchPosUpload(),
      fetchDocTypePermissions(),
    ]);
    isLoading.value = false;
  }

  /// Fetches the DocType definition to determine Field Levels and Role Permissions dynamically.
  Future<void> fetchDocTypePermissions() async {
    try {
      // 1. Fetch DocType Definition
      final response = await _apiProvider.getDocument('DocType', 'POS Upload');

      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];

        // 2. Parse Fields to get Perm Levels
        // Standard fields (owner, creation, etc.) are level 0 by default.
        _fieldLevels['status'] = 0;

        if (data['fields'] != null) {
          for (var field in data['fields']) {
            final String fieldName = field['fieldname'];
            final int permLevel = field['permlevel'] ?? 0;
            _fieldLevels[fieldName] = permLevel;
          }
        }

        // 3. Parse Permissions Table to get Allowed Roles per Level
        if (data['permissions'] != null) {
          for (var perm in data['permissions']) {
            final String role = perm['role'];
            final int level = perm['permlevel'] ?? 0;
            final bool canWrite = perm['write'] == 1;

            if (canWrite) {
              if (!_levelWriteRoles.containsKey(level)) {
                _levelWriteRoles[level] = {};
              }
              _levelWriteRoles[level]!.add(role);
            }
          }
        }
        permissionsLoaded.value = true;
      }
    } catch (e) {
      print('Error fetching permissions: $e');
      // Fallback: If fetch fails, maybe allow nothing or standard defaults
    }
  }

  /// Checks if the current user can edit a specific field based on dynamic configuration.
  bool canEdit(String fieldName) {
    // 1. System Managers usually have full access
    if (_authController.hasRole('System Manager')) return true;

    // 2. Get Permission Level for the field (Default to 0 if not found)
    final int level = _fieldLevels[fieldName] ?? 0;

    // 3. Get Allowed Roles for this Level
    final allowedRoles = _levelWriteRoles[level] ?? {};

    // 4. Check if User has any of the allowed roles
    return _authController.hasAnyRole(allowedRoles.toList());
  }

  Future<void> fetchPosUpload() async {
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
        if (posUpload.value != null) {
          filteredItems.assignAll(posUpload.value!.items);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch POS upload');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    }
  }

  void filterItems(String query) {
    searchQuery.value = query;
    if (query.isEmpty) {
      filteredItems.assignAll(posUpload.value?.items ?? []);
    } else {
      filteredItems.value = posUpload.value?.items
          .where((item) => item.itemName.toLowerCase().contains(query.toLowerCase()))
          .toList() ?? [];
    }
  }

  // 1. IMPLEMENT MIXIN
  @override
  Future<void> reloadDocument() async {
    await fetchPosUpload();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  Future<void> updatePosUpload(Map<String, dynamic> data) async {
    if (isSaving.value) return;

    // 2. USE GUARD
    if (checkStaleAndBlock()) return;

    isSaving.value = true;

    // 3. ADD MODIFIED TIMESTAMP
    if (posUpload.value?.modified != null) {
      data['modified'] = posUpload.value!.modified;
    }

    try {
      final response = await _provider.updatePosUpload(name, data);
      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'POS Upload updated successfully');
        fetchPosUpload();
      } else {
        GlobalSnackbar.error(message: 'Failed to update POS Upload');
      }
    } catch (e) {
      // 4. HANDLE CONFLICT
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: 'Update failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}