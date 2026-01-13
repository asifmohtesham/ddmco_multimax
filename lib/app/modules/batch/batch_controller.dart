import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BatchController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  // Observables for GenericListPage
  final RxList<Batch> batchList = <Batch>[].obs;
  final RxList<Batch> filteredList = <Batch>[].obs; // FIXED: Added this
  final RxBool isLoading = true.obs;
  final RxBool hasMore = true.obs;
  final RxBool isFetchingMore = false.obs;

  // Search & Filter State
  final RxString searchQuery = ''.obs;

  // Expansion Logic
  final RxString expandedBatchName = ''.obs;
  final RxMap<String, String> itemVariants = <String, String>{}.obs;
  final RxBool isLoadingDetails = false.obs;

  // Pagination
  int _currentPage = 0;
  final int _pageSize = 20;

  @override
  void onInit() {
    super.onInit();
    fetchBatches(clear: true);
  }

  Future<void> fetchBatches({bool clear = false, bool isLoadMore = false}) async {
    if (clear) {
      isLoading.value = true;
      _currentPage = 0;
      hasMore.value = true;
      batchList.clear();
      expandedBatchName.value = '';
    } else if (isLoadMore) {
      isFetchingMore.value = true;
    }

    try {
      final filters = <String, dynamic>{};
      if (searchQuery.isNotEmpty) {
        filters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getBatches(
        limit: _pageSize,
        limitStart: _currentPage * _pageSize,
        filters: filters,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newBatches = data.map((e) => Batch.fromJson(e)).toList();

        if (newBatches.length < _pageSize) {
          hasMore.value = false;
        }

        if (clear) {
          batchList.assignAll(newBatches);
        } else {
          batchList.addAll(newBatches);
        }

        _currentPage++;
        _applyFilters();
      }
    } catch (e) {
      GlobalSnackbar.error(message: "Failed to load batches: $e");
    } finally {
      isLoading.value = false;
      isFetchingMore.value = false;
    }
  }

  void onSearchChanged(String query) {
    searchQuery.value = query;
    if (query.isEmpty) {
      fetchBatches(clear: true);
    } else {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (searchQuery.value == query) fetchBatches(clear: true);
      });
    }
  }

  void _applyFilters() {
    filteredList.assignAll(batchList);
  }

  void openBatchForm([String? name]) {
    Get.toNamed(
        AppRoutes.BATCH_FORM,
        arguments: {'name': name ?? '', 'mode': name != null ? 'edit' : 'new'}
    )?.then((_) => fetchBatches(clear: true));
  }

  void toggleExpand(String batchName) {
    if (expandedBatchName.value == batchName) {
      expandedBatchName.value = '';
    } else {
      expandedBatchName.value = batchName;
      _fetchVariantDetails(batchName);
    }
  }

  Future<void> _fetchVariantDetails(String batchName) async {
    final batch = batchList.firstWhereOrNull((b) => b.name == batchName);
    if (batch == null || itemVariants.containsKey(batch.item)) return;

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getItemDetails(batch.item);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final variantOf = response.data['data']['variant_of'];
        itemVariants[batch.item] = (variantOf != null && variantOf.isNotEmpty) ? variantOf : 'N/A';
      }
    } catch (e) {
      itemVariants[batch.item] = 'Error';
    } finally {
      isLoadingDetails.value = false;
    }
  }
}