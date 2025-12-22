import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class MaterialRequestController extends GetxController {
  final MaterialRequestProvider _provider = Get.find<MaterialRequestProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var materialRequests = <MaterialRequest>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var searchQuery = ''.obs;

  // UI State
  var expandedRequestId = ''.obs;

  // Permissions
  var writeRoles = <String>['System Manager'].obs;

  @override
  void onInit() {
    super.onInit();
    fetchMaterialRequests();
    fetchDocTypePermissions();
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
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
        final newRoles = <String>{'System Manager'}; // Always allowed

        for (var p in perms) {
          // Check for Write access (1) at permlevel 0 (Standard fields)
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

  Future<void> deleteMaterialRequest(String name) async {
    GlobalDialog.showConfirmation(
        title: 'Delete Request?',
        message: 'Are you sure you want to delete $name? This action cannot be undone.',
        onConfirm: () async {
          try {
            final response = await _provider.deleteMaterialRequest(name);
            if (response.statusCode == 200 || response.statusCode == 202) {
              GlobalSnackbar.success(message: 'Material Request deleted successfully');
              fetchMaterialRequests(clear: true);
              if (expandedRequestId.value == name) {
                expandedRequestId.value = '';
              }
            } else {
              GlobalSnackbar.error(message: 'Failed to delete document');
            }
          } catch (e) {
            GlobalSnackbar.error(message: 'Error: $e');
          }
        }
    );
  }

  Future<void> fetchMaterialRequests({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        materialRequests.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
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

        if (isLoadMore) {
          materialRequests.addAll(newEntries);
        } else {
          materialRequests.value = newEntries;
        }
        _currentPage++;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to fetch material requests');
    } finally {
      if (isLoadMore) isFetchingMore.value = false;
      else isLoading.value = false;
    }
  }
}