import 'package:get/get.dart';
import 'package:multimax/app/data/models/customer_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';

class PosUploadController extends GetxController {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();
  final CustomerProvider _customerProvider = Get.find<CustomerProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var posUploads = <PosUpload>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedUploadName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedUploadsCache = <String, PosUpload>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'modified'.obs;
  var sortOrder = 'desc'.obs;

  // Search
  var searchQuery = ''.obs;

  // Customer list for filter picker
  var customers = <CustomerEntry>[].obs;
  var isFetchingCustomers = false.obs;

  PosUpload? get detailedUpload =>
      _detailedUploadsCache[expandedUploadName.value];

  @override
  void onInit() {
    super.onInit();
    fetchPosUploads();
    fetchCustomers();
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<void> fetchCustomers() async {
    if (isFetchingCustomers.value) return;
    isFetchingCustomers.value = true;
    try {
      final response = await _customerProvider.getCustomers(limit: 0);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        customers.value =
            data.map((json) => CustomerEntry.fromJson(json)).toList();
      }
    } catch (_) {
    } finally {
      isFetchingCustomers.value = false;
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) fetchPosUploads(clear: true);
    });
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> fetchPosUploads(
      {bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        posUploads.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final Map<String, dynamic> queryFilters = Map.from(activeFilters);
      if (searchQuery.value.isNotEmpty) {
        queryFilters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getPosUploads(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: queryFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newUploads =
        data.map((json) => PosUpload.fromJson(json)).toList();

        if (newUploads.length < _limit) hasMore.value = false;

        if (isLoadMore) {
          posUploads.addAll(newUploads);
        } else {
          posUploads.value = newUploads;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch POS uploads');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      if (isLoadMore) {
        isFetchingMore.value = false;
      } else {
        isLoading.value = false;
      }
    }
  }

  Future<void> _fetchAndCacheUploadDetails(String name) async {
    if (_detailedUploadsCache.containsKey(name)) return;
    isLoadingDetails.value = true;
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final upload = PosUpload.fromJson(response.data['data']);
        _detailedUploadsCache[name] = upload;
      }
    } catch (_) {
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedUploadName.value == name) {
      expandedUploadName.value = '';
    } else {
      expandedUploadName.value = name;
      _fetchAndCacheUploadDetails(name);
    }
  }
}
