import 'package:flutter/material.dart';
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

  // Cache for POS Customer Names
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

  @override
  void onReady() {
    super.onReady();
    if (Get.arguments is Map && Get.arguments['openCreate'] == true) {
      openCreateDialog();
    }
  }

  // ... (Fetch logic unchanged) ...
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

  Future<void> _fetchAssociatedCustomers(List<PackingSlip> slips) async {
    final poNumbers = slips
        .map((s) => s.customPoNo)
        .where((po) => po != null && po.isNotEmpty && !posCustomerMap.containsKey(po))
        .toSet()
        .toList();

    if (poNumbers.isEmpty) return;

    try {
      final response = await _posProvider.getPosUploads(
        limit: 100,
        filters: {'name': ['in', poNumbers]},
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

    final grouped = groupBy(list, (PackingSlip slip) {
      if (slip.customPoNo != null && slip.customPoNo!.isNotEmpty) {
        return slip.customPoNo!;
      }
      if (slip.deliveryNote.isNotEmpty) {
        return slip.deliveryNote;
      }
      return 'Other';
    });

    grouped.forEach((key, list) {
      list.sort((a, b) => (a.fromCaseNo ?? 0).compareTo(b.fromCaseNo ?? 0));
    });

    return grouped;
  }

  void onSearchChanged(String val) {
    searchQuery.value = val;
  }

  // --- Creation Logic ---

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

  // Moved from Screen
  void openCreateDialog() {
    fetchDeliveryNotesForSelection();

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Delivery Note',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Get.back(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: filterDeliveryNotes,
                    decoration: const InputDecoration(
                      labelText: 'Search Delivery Notes',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Obx(() {
                      if (isFetchingDNs.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (deliveryNotesForSelection.isEmpty) {
                        return const Center(child: Text('No Delivery Notes found.'));
                      }

                      return ListView.separated(
                        controller: scrollController,
                        itemCount: deliveryNotesForSelection.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final dn = deliveryNotesForSelection[index];
                          final hasPO = dn.poNo != null && dn.poNo!.isNotEmpty;
                          final title = hasPO ? dn.poNo! : dn.name;
                          final subtitle = hasPO
                              ? '${dn.name} • ${dn.customer}'
                              : dn.customer;

                          return ListTile(
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Get.back();
                              initiatePackingSlipCreation(dn);
                            },
                          );
                        },
                      );
                    }),
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