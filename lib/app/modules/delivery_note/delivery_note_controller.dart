import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/customer_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/providers/customer_provider.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class DeliveryNoteController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();
  final WarehouseProvider _warehouseProvider = Get.find<WarehouseProvider>();
  final CustomerProvider _customerProvider = Get.find<CustomerProvider>();

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

  // Search
  var searchQuery = ''.obs;

  // POS Upload selection
  var isFetchingPosUploads = false.obs;
  var posUploadsForSelection = <PosUpload>[].obs;
  var posUploadSearchQuery = ''.obs;
  List<PosUpload> _allFetchedPosUploads = [];

  // Users for filter
  var users = <User>[].obs;
  var isFetchingUsers = false.obs;

  // Warehouses for filter
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // Customers for filter
  var customers = <CustomerEntry>[].obs;
  var isFetchingCustomers = false.obs;

  DeliveryNote? get detailedNote => _detailedNotesCache[expandedNoteName.value];

  @override
  void onInit() {
    super.onInit();
    fetchDeliveryNotes();
    fetchUsers();
    fetchWarehouses();
    fetchCustomers();
  }

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments is Map && Get.arguments['openCreate'] == true) {
      openCreateDialog();
    }
  }

  // ---------------------------------------------------------------------------
  // Filter / Sort
  // ---------------------------------------------------------------------------

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    searchQuery.value = '';
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchDeliveryNotes(isLoadMore: false, clear: true);
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (searchQuery.value == val) {
        fetchDeliveryNotes(clear: true);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------

  Future<void> fetchDeliveryNotes(
      {bool isLoadMore = false, bool clear = false}) async {
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
      final Map<String, dynamic> queryFilters = Map.from(activeFilters);
      if (searchQuery.value.isNotEmpty) {
        queryFilters['name'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getDeliveryNotes(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: queryFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newNotes =
            data.map((json) => DeliveryNote.fromJson(json)).toList();
        if (newNotes.length < _limit) hasMore.value = false;
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

  Future<void> fetchUsers() async {
    if (users.isNotEmpty) return;
    isFetchingUsers.value = true;
    try {
      final response = await _userProvider.getUsers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        users.value = data.map((json) => User.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching users: $e');
    } finally {
      isFetchingUsers.value = false;
    }
  }

  Future<void> fetchWarehouses() async {
    if (warehouses.isNotEmpty) return;
    isFetchingWarehouses.value = true;
    try {
      final response = await _warehouseProvider.getWarehouses();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        warehouses.value = data.map((e) => e['name'].toString()).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> fetchCustomers() async {
    if (customers.isNotEmpty) return;
    isFetchingCustomers.value = true;
    try {
      final response = await _customerProvider.getCustomers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        customers.value =
            data.map((json) => CustomerEntry.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching customers: $e');
    } finally {
      isFetchingCustomers.value = false;
    }
  }

  Future<void> _fetchAndCacheNoteDetails(String name) async {
    if (_detailedNotesCache.containsKey(name)) return;
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

  // ---------------------------------------------------------------------------
  // POS Upload selection
  // ---------------------------------------------------------------------------

  Future<void> fetchPosUploadsForSelection() async {
    isFetchingPosUploads.value = true;
    try {
      final response = await _posUploadProvider.getPosUploads(limit: 100);
      final List<PosUpload> fetchedUploads = [];
      if (response.statusCode == 200 && response.data['data'] != null) {
        fetchedUploads.addAll(
            (response.data['data'] as List)
                .map((json) => PosUpload.fromJson(json)));
      }
      _allFetchedPosUploads = fetchedUploads
          .where((u) => u.status == 'Pending' || u.status == 'In Progress')
          .toList();
      posUploadsForSelection.assignAll(_allFetchedPosUploads);
      posUploadSearchQuery.value = '';
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch POS Uploads: $e');
    } finally {
      isFetchingPosUploads.value = false;
    }
  }

  void filterPosUploads(String query) {
    posUploadSearchQuery.value = query;
    if (query.isEmpty) {
      posUploadsForSelection.assignAll(_allFetchedPosUploads);
    } else {
      final q = query.toLowerCase();
      posUploadsForSelection.value = _allFetchedPosUploads
          .where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.customer.toLowerCase().contains(q) ||
              u.status.toLowerCase().contains(q))
          .toList();
    }
  }

  Future<void> createNewDeliveryNote(PosUpload? selectedPosUpload) async {
    if (selectedPosUpload != null) {
      try {
        final existingDraft = deliveryNotes.firstWhereOrNull(
            (n) => n.poNo == selectedPosUpload.name && n.docstatus == 0);
        if (existingDraft != null) {
          Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
            'name': existingDraft.name,
            'mode': 'edit',
            'posUploadCustomer': selectedPosUpload.customer,
            'posUploadName': selectedPosUpload.name,
          });
          return;
        }
        final response = await _provider.getDeliveryNotes(
            limit: 1,
            filters: {'po_no': selectedPosUpload.name, 'docstatus': 0});
        if (response.statusCode == 200 &&
            response.data['data'] != null &&
            (response.data['data'] as List).isNotEmpty) {
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
      }
      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM, arguments: {
        'name': '',
        'mode': 'new',
        'posUploadCustomer': selectedPosUpload.customer,
        'posUploadName': selectedPosUpload.name,
      });
    } else {
      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
          arguments: {'name': '', 'mode': 'new'});
    }
  }

  // ---------------------------------------------------------------------------
  // Create dialog (POS Upload selection bottom sheet)
  // ---------------------------------------------------------------------------

  void openCreateDialog() {
    fetchPosUploadsForSelection();
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Select POS Upload',
                            style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: Get.back),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: TextField(
                      onChanged: filterPosUploads,
                      decoration: InputDecoration(
                        hintText: 'Search POS Uploads',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingPosUploads.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (posUploadsForSelection.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              const Text('No POS Uploads found.',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: posUploadsForSelection.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final posUpload = posUploadsForSelection[index];
                          final statusColor = posUpload.status == 'Pending'
                              ? Colors.orange
                              : Colors.blue;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            title: Text(posUpload.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.person_outline,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Text(posUpload.customer,
                                          overflow: TextOverflow.ellipsis)),
                                ]),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(posUpload.status,
                                      style: const TextStyle(fontSize: 12)),
                                ]),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right,
                                color: Colors.grey),
                            onTap: () {
                              Get.back();
                              createNewDeliveryNote(posUpload);
                            },
                          );
                        },
                      );
                    }),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Get.back();
                          createNewDeliveryNote(null);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Skip & Create Blank Note'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }
}
