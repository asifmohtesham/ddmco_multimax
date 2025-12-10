import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

class PackingSlipController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posProvider = Get.find<PosUploadProvider>();
  final HomeController _homeController = Get.find<HomeController>();

  var isLoading = true.obs;
  var isFetchingMore = false.obs;
  var hasMore = true.obs;
  var packingSlips = <PackingSlip>[].obs;
  final int _limit = 20;
  int _currentPage = 0;

  var expandedSlipName = ''.obs;
  var expandedGroup = ''.obs;

  final activeFilters = <String, dynamic>{}.obs;
  var sortField = 'creation'.obs;
  var sortOrder = 'desc'.obs;

  // Search State
  var searchQuery = ''.obs;

  // Cache for POS Customer Names: { "POS-123": "Customer Name" }
  var posCustomerMap = <String, String>{}.obs;

  // For DN Selection
  var isFetchingDNs = false.obs;
  var deliveryNotesForSelection = <DeliveryNote>[].obs;
  List<DeliveryNote> _allFetchedDNs = [];

  @override
  void onInit() {
    super.onInit();
    _homeController.activeScreen.value = ActiveScreen.packingSlip;
    fetchPackingSlips();
  }

  void applyFilters(Map<String, dynamic> filters) {
    activeFilters.value = filters;
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  void setSort(String field, String order) {
    sortField.value = field;
    sortOrder.value = order;
    fetchPackingSlips(isLoadMore: false, clear: true);
  }

  Future<void> fetchPackingSlips({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        packingSlips.clear();
        _currentPage = 0;
        hasMore.value = true;
      }
    }

    try {
      final response = await _provider.getPackingSlips(
        limit: _limit,
        limitStart: _currentPage * _limit,
        filters: activeFilters,
        orderBy: '${sortField.value} ${sortOrder.value}',
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final newSlips = data.map((json) => PackingSlip.fromJson(json)).toList();

        if (newSlips.length < _limit) {
          hasMore.value = false;
        }

        if (isLoadMore) {
          packingSlips.addAll(newSlips);
        } else {
          packingSlips.value = newSlips;
        }

        // Fetch Customers for new slips
        _fetchAssociatedCustomers(newSlips);

        _currentPage++;
      } else {
        Get.snackbar('Error', 'Failed to fetch packing slips');
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

  // Look up Customer Name from POS Upload if missing in Packing Slip
  Future<void> _fetchAssociatedCustomers(List<PackingSlip> slips) async {
    final poNumbers = slips
        .map((s) => s.customPoNo)
        .where((po) => po != null && po.isNotEmpty && !posCustomerMap.containsKey(po))
        .toSet()
        .toList();

    if (poNumbers.isEmpty) return;

    try {
      // Bulk fetch logic if API supports 'in' filter, else iterate
      // POS Upload usually allows filtering by name
      final response = await _posProvider.getPosUploads(
        limit: 100,
        filters: {'name': ['in', poNumbers]},
        // We only need name and customer fields
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        for (var doc in response.data['data']) {
          final String name = doc['name'];
          final String customer = doc['customer'] ?? 'Unknown';
          posCustomerMap[name] = customer;
        }
      }
    } catch (e) {
      print('Error fetching POS customers: $e');
    }
  }

  String getCustomerName(String? poNo) {
    if (poNo == null) return '';
    return posCustomerMap[poNo] ?? '';
  }

  void toggleExpand(String name) {
    if (expandedSlipName.value == name) {
      expandedSlipName.value = '';
    } else {
      expandedSlipName.value = name;
    }
  }

  void toggleGroup(String key) {
    if (expandedGroup.value == key) {
      expandedGroup.value = '';
    } else {
      expandedGroup.value = key;
    }
  }

  Map<String, List<PackingSlip>> get groupedPackingSlips {
    // 1. Filter
    var list = packingSlips.toList();
    if (searchQuery.value.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      list = list.where((slip) {
        final customer = slip.customer ?? posCustomerMap[slip.customPoNo] ?? '';
        return slip.name.toLowerCase().contains(q) ||
            slip.deliveryNote.toLowerCase().contains(q) ||
            (slip.customPoNo ?? '').toLowerCase().contains(q) ||
            customer.toLowerCase().contains(q);
      }).toList();
    }

    // 2. Group
    final grouped = groupBy(list, (PackingSlip slip) {
      if (slip.customPoNo != null && slip.customPoNo!.isNotEmpty) {
        return slip.customPoNo!;
      }
      if (slip.deliveryNote.isNotEmpty) {
        return slip.deliveryNote;
      }
      return 'Other';
    });

    // 3. Sort inside groups
    grouped.forEach((key, list) {
      list.sort((a, b) => (a.fromCaseNo ?? 0).compareTo(b.fromCaseNo ?? 0));
    });

    return grouped;
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
  }

  Future<void> fetchDeliveryNotesForSelection() async {
    isFetchingDNs.value = true;
    try {
      final response = await _dnProvider.getDeliveryNotes(
          limit: 100,
          orderBy: 'modified desc',
          filters: {'docstatus': 0}
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        _allFetchedDNs = data.map((json) => DeliveryNote.fromJson(json)).toList();
        deliveryNotesForSelection.value = _allFetchedDNs;
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch Delivery Notes');
    } finally {
      isFetchingDNs.value = false;
    }
  }

  void filterDeliveryNotes(String query) {
    if (query.isEmpty) {
      deliveryNotesForSelection.value = _allFetchedDNs;
    } else {
      final q = query.toLowerCase();
      deliveryNotesForSelection.value = _allFetchedDNs.where((dn) {
        final poNo = dn.poNo?.toLowerCase() ?? '';
        final name = dn.name.toLowerCase();
        final customer = dn.customer.toLowerCase();
        return poNo.contains(q) || name.contains(q) || customer.contains(q);
      }).toList();
    }
  }

  Future<void> initiatePackingSlipCreation(DeliveryNote dn) async {
    int nextCaseNo = 1;
    try {
      final response = await _provider.getPackingSlips(
          limit: 1,
          filters: {'delivery_note': dn.name},
          orderBy: 'to_case_no desc'
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        if (data.isNotEmpty) {
          final lastSlip = PackingSlip.fromJson(data[0]);
          if (lastSlip.toCaseNo != null) {
            nextCaseNo = lastSlip.toCaseNo! + 1;
          }
        }
      }
    } catch (e) {
      print('Error determining next case no: $e');
    }

    Get.toNamed(AppRoutes.PACKING_SLIP_FORM, arguments: {
      'name': '',
      'mode': 'new',
      'deliveryNote': dn.name,
      'customPoNo': dn.poNo,
      'nextCaseNo': nextCaseNo
    });
  }
}