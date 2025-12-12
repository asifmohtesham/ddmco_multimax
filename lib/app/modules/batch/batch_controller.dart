// app/modules/batch/batch_controller.dart
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class BatchController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  var batches = <Batch>[].obs;
  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;

  final int _limit = 20;
  int _currentPage = 0;
  var searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchBatches();
  }

  Future<void> fetchBatches({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        batches.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final filters = <String, dynamic>{};
      if (searchQuery.value.isNotEmpty) {
        // Search by Batch ID or Item Code
        filters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getBatches(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: filters,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newBatches = data.map((json) => Batch.fromJson(json)).toList();

        if (newBatches.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          batches.addAll(newBatches);
        } else {
          batches.value = newBatches;
        }
        _currentPage++;
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch batches: $e');
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    // Debounce or simple delay could be added here
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchBatches(clear: true);
      }
    });
  }

  void openBatchForm([String? name]) {
    Get.toNamed(
        AppRoutes.BATCH_FORM,
        arguments: {'name': name ?? '', 'mode': name != null ? 'edit' : 'new'}
    )?.then((value) => fetchBatches(clear: true));
  }
}