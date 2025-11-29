import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';

class PosUploadController extends GetxController {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();

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

  @override
  void onInit() {
    super.onInit();
    fetchPosUploads();
  }

  PosUpload? get detailedUpload => _detailedUploadsCache[expandedUploadName.value];

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPosUploads(isLoadMore: false, clear: true);
  }

  Future<void> fetchPosUploads({bool isLoadMore = false, bool clear = false}) async {
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
      final response = await _provider.getPosUploads(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newUploads = data.map((json) => PosUpload.fromJson(json)).toList();

        if (newUploads.length < _limit) {
          hasMore.value = false;
        }

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
    if (_detailedUploadsCache.containsKey(name)) {
      return;
    }

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        print(response.data); // Log the full response
        final upload = PosUpload.fromJson(response.data['data']);
        _detailedUploadsCache[name] = upload;
      } else {
        Get.snackbar('Error', 'Failed to fetch upload details');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
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
