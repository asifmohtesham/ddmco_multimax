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

  // ── Pagination ────────────────────────────────────────────────────────────
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var materialRequests = <MaterialRequest>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  // ── Search & Filter ───────────────────────────────────────────────────────
  var searchQuery = ''.obs;
  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  // ── Expand / Detail cache (mirrors DeliveryNoteController) ────────────────
  var expandedRequestId = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailCache = <String, MaterialRequest>{}.obs;

  // ── Permissions ───────────────────────────────────────────────────────────
  var writeRoles = <String>['System Manager'].obs;

  MaterialRequest? get detailedRequest => _detailCache[expandedRequestId.value];

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    fetchMaterialRequests();
    fetchDocTypePermissions();
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments is Map && Get.arguments['openCreate'] == true) {
      openCreateForm();
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchMaterialRequests(clear: true);
      }
    });
  }

  // ── Filters ───────────────────────────────────────────────────────────────
  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchMaterialRequests(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchMaterialRequests(clear: true);
  }

  // ── Sort ──────────────────────────────────────────────────────────────────
  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchMaterialRequests(clear: true);
  }

  // ── Expand / Detail ───────────────────────────────────────────────────────
  void toggleExpand(String name) {
    if (expandedRequestId.value == name) {
      expandedRequestId.value = '';
    } else {
      expandedRequestId.value = name;
      _fetchAndCacheDetail(name);
    }
  }

  Future<void> _fetchAndCacheDetail(String name) async {
    if (_detailCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getMaterialRequest(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = MaterialRequest.fromJson(response.data['data']);
        _detailCache[name] = entry;
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch request details');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isLoadingDetails.value = false;
    }
  }

  // ── Fetch List ────────────────────────────────────────────────────────────
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
      final Map<String, dynamic> filters = Map.from(activeFilters);
      if (searchQuery.value.isNotEmpty) {
        filters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getMaterialRequests(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: filters,
        // orderBy supported if provider exposes it; gracefully ignored if not
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
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────
  Future<void> fetchDocTypePermissions() async {
    try {
      final response = await _apiProvider.getDocument('DocType', 'Material Request');
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> perms = response.data['data']['permissions'] ?? [];
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

  // ── CRUD ──────────────────────────────────────────────────────────────────
  void openCreateForm() {
    Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': '', 'mode': 'new'});
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
            _detailCache.remove(name);
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
      },
    );
  }
}
