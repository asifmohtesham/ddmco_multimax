import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class MaterialRequestController extends GetxController {
  final MaterialRequestProvider _provider = Get.find<MaterialRequestProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Observables for GenericListPage
  final RxList<MaterialRequest> materialRequests = <MaterialRequest>[].obs;
  final RxList<MaterialRequest> filteredList = <MaterialRequest>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool hasMore = true.obs;
  final RxBool isFetchingMore = false.obs;

  // Search
  final RxString searchQuery = ''.obs;

  // Expansion & UI State
  final RxString expandedRequestId = ''.obs;

  // Permissions
  final RxList<String> writeRoles = <String>['System Manager'].obs;

  // Pagination
  final int _limit = 20;
  int _currentPage = 0;

  @override
  void onInit() {
    super.onInit();
    fetchMaterialRequests(clear: true);
    fetchDocTypePermissions();
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    // Debounce search
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchMaterialRequests(clear: true);
      }
    });
  }

  void toggleExpand(String name) {
    if (expandedRequestId.value == name) {
      expandedRequestId.value = '';
    } else {
      expandedRequestId.value = name;
    }
  }

  Future<void> fetchDocTypePermissions() async {
    try {
      final response = await _apiProvider.getDocument('DocType', 'Material Request');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        final List<dynamic> perms = data['permissions'] ?? [];
        final newRoles = <String>{'System Manager'};

        for (var p in perms) {
          if (p['write'] == 1 && (p['permlevel'] == 0 || p['permlevel'] == null)) {
            newRoles.add(p['role']);
          }
        }
        writeRoles.assignAll(newRoles.toList());
      }
    } catch (e) {
      print('Error fetching permissions: $e');
    }
  }

  Future<void> fetchMaterialRequests({bool isLoadMore = false, bool clear = false}) async {
    if (clear) {
      isLoading.value = true;
      materialRequests.clear();
      _currentPage = 0;
      hasMore.value = true;
      expandedRequestId.value = '';
    } else if (isLoadMore) {
      isFetchingMore.value = true;
    }

    try {
      final Map<String, dynamic> filters = {};
      if (searchQuery.value.isNotEmpty) {
        filters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getMaterialRequests(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: filters,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newEntries = data.map((json) => MaterialRequest.fromJson(json)).toList();

        if (newEntries.length < _limit) hasMore.value = false;

        if (clear) {
          materialRequests.assignAll(newEntries);
        } else {
          materialRequests.addAll(newEntries);
        }

        _currentPage++;
        _applyFilters();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to fetch material requests');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void _applyFilters() {
    // API handles search, so filteredList is essentially the main list
    filteredList.assignAll(materialRequests);
  }

  // --- Actions ---

  void openForm(String name, {String mode = 'view'}) {
    Get.toNamed(
        AppRoutes.MATERIAL_REQUEST_FORM,
        arguments: {'name': name, 'mode': mode}
    )?.then((_) => fetchMaterialRequests(clear: true));
  }

  Future<void> deleteMaterialRequest(String name) async {
    GlobalDialog.showConfirmation(
        title: 'Delete Request?',
        message: 'Are you sure you want to delete $name? This action cannot be undone.',
        onConfirm: () async {
          try {
            final response = await _provider.deleteMaterialRequest(name);
            if (response.statusCode == 200 || response.statusCode == 202) {
              GlobalSnackbar.success(message: 'Deleted successfully');
              fetchMaterialRequests(clear: true);
            } else {
              GlobalSnackbar.error(message: 'Failed to delete');
            }
          } catch (e) {
            GlobalSnackbar.error(message: 'Error: $e');
          }
        }
    );
  }
}