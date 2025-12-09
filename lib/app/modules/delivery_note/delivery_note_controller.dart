
import 'package:get/get.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class DeliveryNoteController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();

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
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  // For POS Upload selection dialog
  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;
  var posUploadSearchQuery = ''.obs;
  List<PosUpload> _allFetchedPosUploads = []; // Store all fetched for local filtering

  DeliveryNote? get detailedNote => _detailedNotesCache[expandedNoteName.value];

  @override
  void onInit() {
    super.onInit();
    fetchDeliveryNotes();
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
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
        orderBy: '${sortField.value} ${sortOrder.value}',
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
      }
      if (isLoading.value) {
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

  Future<void> fetchPosUploadsForSelection() async {
    isFetchingPosUploads.value = true;
    try {
      final response = await _posUploadProvider.getPosUploads(limit: 100);

      final List<PosUpload> fetchedUploads = [];
      if (response.statusCode == 200 && response.data['data'] != null) {
        fetchedUploads.addAll((response.data['data'] as List).map((json) {
          final posUpload = PosUpload.fromJson(json);
          // print('Fetched POS Upload: ${posUpload.name}, Status: ${posUpload.status}'); 
          return posUpload;
        }).toList());
      }
      
      // Filter locally: Keep if status is 'Pending' (including null/empty) or 'In Progress'
      _allFetchedPosUploads = fetchedUploads.where((upload) {
        final status = upload.status;
        return status == 'Pending' || status == 'In Progress';
      }).toList();

      posUploadsForSelection.assignAll(_allFetchedPosUploads);
      posUploadSearchQuery.value = ''; 
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch POS Uploads for selection: $e');
    } finally {
      isFetchingPosUploads.value = false;
    }
  }

  void filterPosUploads(String query) {
    posUploadSearchQuery.value = query;
    if (query.isEmpty) {
      posUploadsForSelection.assignAll(_allFetchedPosUploads);
    } else {
      posUploadsForSelection.value = _allFetchedPosUploads
          .where((upload) => upload.name.toLowerCase().contains(query.toLowerCase()) ||
                          upload.customer.toLowerCase().contains(query.toLowerCase()) ||
                          upload.status.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
  }

  Future<void> createNewDeliveryNote(PosUpload? selectedPosUpload) async {
    if (selectedPosUpload != null) {
      // Check for existing Draft Delivery Note with matching PO No
      try {
        // We can search locally first if the list is likely up to date, 
        // but for correctness, a quick API check is safer or iterate through current list.
        // Let's iterate through current list first as it's faster.
        final existingDraft = deliveryNotes.firstWhereOrNull((note) => 
            note.poNo == selectedPosUpload.name && note.docstatus == 0);

        if (existingDraft != null) {
          // Found local match
          Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
            'name': existingDraft.name,
            'mode': 'edit',
            'posUploadCustomer': selectedPosUpload.customer,
            'posUploadName': selectedPosUpload.name,
          });
          return;
        }

        // If not found locally, query the API to be sure (optional but robust)
        final response = await _provider.getDeliveryNotes(
          limit: 1, 
          filters: {'po_no': selectedPosUpload.name, 'docstatus': 0}
        );
        
        if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
           final noteData = response.data['data'][0];
           Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
            'name': noteData['name'],
            'mode': 'edit',
            'posUploadCustomer': selectedPosUpload.customer,
            'posUploadName': selectedPosUpload.name,
          });
          return;
        }

      } catch (e) {
        print('Error checking for existing draft: $e');
        // Proceed to create new if check fails
      }

      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
        'name': '',
        'mode': 'new',
        'posUploadCustomer': selectedPosUpload.customer,
        'posUploadName': selectedPosUpload.name,
      });
    } else {
      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {'name': '', 'mode': 'new'});
    }
  }
}
