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

  // Expansion Logic
  var expandedBatchName = ''.obs;
  var isLoadingDetails = false.obs;
  var itemVariants = <String, String>{}.obs; // Cache for Item Variants

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
        expandedBatchName.value = ''; // Reset expansion
      }
    }

    try {
      final filters = <String, dynamic>{};
      if (searchQuery.value.isNotEmpty) {
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

  // --- Expansion Logic ---

  void toggleExpand(String batchName) {
    if (expandedBatchName.value == batchName) {
      expandedBatchName.value = ''; // Collapse
    } else {
      expandedBatchName.value = batchName; // Expand
      _fetchVariantDetails(batchName);
    }
  }

  Future<void> _fetchVariantDetails(String batchName) async {
    // Find the batch object
    final batch = batches.firstWhereOrNull((b) => b.name == batchName);
    if (batch == null || itemVariants.containsKey(batch.item)) return;

    isLoadingDetails.value = true;
    try {
      // We need to fetch the ITEM details to get 'variant_of'
      final response = await _provider.getItemDetails(batch.item);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        final variantOf = itemData['variant_of'] ?? '';
        itemVariants[batch.item] = variantOf.isNotEmpty ? variantOf : 'N/A';
      }
    } catch (e) {
      print('Error fetching item variant: $e');
      itemVariants[batch.item] = 'Error';
    } finally {
      isLoadingDetails.value = false;
    }
  }
}