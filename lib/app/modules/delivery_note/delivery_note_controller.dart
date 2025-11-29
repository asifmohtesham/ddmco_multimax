import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';

class DeliveryNoteController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var deliveryNotes = <DeliveryNote>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedNoteName = ''.obs;
  var isLoadingDetails = false.obs;
  final _detailedNotesCache = <String, DeliveryNote>{}.obs;

  final activeFilters = <String, dynamic>{}.obs;

  @override
  void onInit() {
    super.onInit();
    fetchDeliveryNotes();
  }

  DeliveryNote? get detailedNote => _detailedNotesCache[expandedNoteName.value];

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  Future<void> fetchDeliveryNotes({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        deliveryNotes.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final response = await _provider.getDeliveryNotes(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newNotes = data.map((json) => DeliveryNote.fromJson(json)).toList();

        if (newNotes.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          deliveryNotes.addAll(newNotes);
        } else {
          deliveryNotes.value = newNotes;
        }
        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch delivery notes');
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

  Future<void> _fetchAndCacheNoteDetails(String name) async {
    if (_detailedNotesCache.containsKey(name)) {
      return;
    }

    isLoadingDetails.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        _detailedNotesCache[name] = note;
      } else {
        Get.snackbar('Error', 'Failed to fetch note details');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoadingDetails.value = false;
    }
  }

  void toggleExpand(String name) {
    if (expandedNoteName.value == name) {
      expandedNoteName.value = '';
    } else {
      expandedNoteName.value = name;
      _fetchAndCacheNoteDetails(name);
    }
  }
}
