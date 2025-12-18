import 'package:get/get.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';

class MaterialRequestController extends GetxController {
  final MaterialRequestProvider _provider = Get.find<MaterialRequestProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var materialRequests = <MaterialRequest>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchMaterialRequests();
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchMaterialRequests(clear: true);
      }
    });
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
      Get.snackbar('Error', 'Failed to fetch material requests');
    } finally {
      if (isLoadMore) isFetchingMore.value = false;
      else isLoading.value = false;
    }
  }
}