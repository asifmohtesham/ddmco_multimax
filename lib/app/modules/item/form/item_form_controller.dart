import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';

class ItemFormController extends GetxController
    with GetTickerProviderStateMixin {
  final ItemProvider _provider = Get.find<ItemProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  late final TabController tabController;

  String itemCode = '';
  var item = Rx<Item?>(null);
  var isLoading = true.obs;

  var attachments = <Map<String, dynamic>>[].obs;

  var stockLevels = <WarehouseStock>[].obs;
  var stockLedgerEntries = <Map<String, dynamic>>[].obs;
  var batchHistory = <Map<String, dynamic>>[].obs;

  var ledgerDateRange = Rx<DateTimeRange?>(null);

  var isLoadingStock = false.obs;
  var isLoadingLedger = false.obs;
  var isLoadingBatches = false.obs;

  // ── Warehouse filter ────────────────────────────────────────────────────
  /// null = All Warehouses (no filter applied).
  var selectedWarehouse = Rx<String?>(null);

  /// Deduplicated, sorted list of warehouses derived from the raw stockLevels
  /// list.  Used to build the filter chip row in the UI.
  List<String> get availableWarehouses {
    final seen = <String>{};
    final warehouses = <String>[];
    for (final s in stockLevels) {
      if (s.warehouse.isNotEmpty && seen.add(s.warehouse)) {
        warehouses.add(s.warehouse);
      }
    }
    warehouses.sort();
    return warehouses;
  }

  /// stockLevels filtered by [selectedWarehouse].
  List<WarehouseStock> get filteredStockLevels {
    final wh = selectedWarehouse.value;
    if (wh == null) return stockLevels;
    return stockLevels.where((s) => s.warehouse == wh).toList();
  }

  /// batchHistory filtered by [selectedWarehouse].
  List<Map<String, dynamic>> get filteredBatchHistory {
    final wh = selectedWarehouse.value;
    if (wh == null) return batchHistory;
    return batchHistory
        .where((b) => (b['warehouse'] ?? '') == wh)
        .toList();
  }

  void onWarehouseChanged(String? warehouse) {
    selectedWarehouse.value = warehouse;
  }

  void clearWarehouseFilter() {
    selectedWarehouse.value = null;
  }
  // ────────────────────────────────────────────────────────────────────────

  bool _stockTabLoaded = false;
  bool _attachmentsTabLoaded = false;

  final Map<String, Map<String, dynamic>> _enrichmentCache = {};

  @override
  void onInit() {
    super.onInit();
    tabController = TabController(length: 4, vsync: this);
    tabController.addListener(_onTabChanged);

    final args = Get.arguments;
    if (args != null) {
      if (args is Map && args['itemCode'] != null) {
        itemCode = args['itemCode'];
        _loadCoreData();
      } else if (args is String) {
        itemCode = args;
        _loadCoreData();
      }
    }
  }

  @override
  void onClose() {
    tabController.removeListener(_onTabChanged);
    tabController.dispose();
    super.onClose();
  }

  void _onTabChanged() {
    if (tabController.indexIsChanging) return;
    switch (tabController.index) {
      case 1:
        if (!_stockTabLoaded) {
          _stockTabLoaded = true;
          fetchDashboardData();
        }
        break;
      case 3:
        if (!_attachmentsTabLoaded) {
          _attachmentsTabLoaded = true;
          fetchAttachments();
        }
        break;
    }
  }

  void loadItem(String code) {
    itemCode = code;
    _loadCoreData();
  }

  void _loadCoreData() {
    fetchItemDetails();
  }

  void updateLedgerDateRange(DateTimeRange range) {
    ledgerDateRange.value = range;
    fetchStockLedger();
  }

  void clearLedgerDateRange() {
    ledgerDateRange.value = null;
    fetchStockLedger();
  }

  Future<void> fetchItemDetails() async {
    if (itemCode.isEmpty) return;
    isLoading.value = true;
    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        item.value = Item.fromJson(response.data['data']);
      } else {
        GlobalSnackbar.error(message: 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchAttachments() async {
    if (itemCode.isEmpty) return;
    try {
      final response = await _apiProvider.getDocumentList(
        'File',
        filters: {
          'attached_to_doctype': 'Item',
          'attached_to_name': itemCode,
        },
        fields: ['file_name', 'file_url', 'is_private'],
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        attachments.value =
            List<Map<String, dynamic>>.from(response.data['data']);
      }
    } catch (e) {
      if (kDebugMode) log('Error fetching attachments: $e');
    }
  }

  Future<void> fetchDashboardData() async {
    if (itemCode.isEmpty) return;
    fetchStockLevels();
    fetchStockLedger();
    fetchBatchHistory();
  }

  Future<void> fetchStockLevels() async {
    isLoadingStock.value = true;
    // Reset filter so a stale selection never hides data after a refresh.
    selectedWarehouse.value = null;
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        stockLevels.value = data
            .whereType<Map<String, dynamic>>()
            .map((json) => WarehouseStock.fromJson(json))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) log('Error fetching stock levels: $e');
    } finally {
      isLoadingStock.value = false;
    }
  }

  Future<void> fetchStockLedger() async {
    isLoadingLedger.value = true;
    try {
      final response = await _provider.getStockLedger(
        itemCode,
        fromDate: ledgerDateRange.value?.start,
        toDate: ledgerDateRange.value?.end,
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        List<Map<String, dynamic>> entries =
            List<Map<String, dynamic>>.from(response.data['data']);

        final List<String> dnToFetch = [];
        final List<String> seToFetch = [];

        for (var entry in entries) {
          final type = entry['voucher_type'];
          final no = entry['voucher_no'];
          if (no == null) continue;
          if (_enrichmentCache.containsKey(no)) continue;
          if (type == 'Delivery Note') dnToFetch.add(no);
          if (type == 'Stock Entry') seToFetch.add(no);
        }

        if (dnToFetch.isNotEmpty) {
          try {
            final dnResponse = await _apiProvider.getDocumentList(
              'Delivery Note',
              filters: {'name': ['in', dnToFetch]},
              fields: ['name', 'customer', 'po_no'],
            );
            if (dnResponse.statusCode == 200 &&
                dnResponse.data['data'] != null) {
              for (var d in dnResponse.data['data']) {
                _enrichmentCache[d['name']] = d;
              }
            }
          } catch (e) {
            if (kDebugMode) log('Error fetching DN details: $e');
          }
        }

        if (seToFetch.isNotEmpty) {
          try {
            final seResponse = await _apiProvider.getDocumentList(
              'Stock Entry',
              filters: {'name': ['in', seToFetch]},
              fields: ['name', 'stock_entry_type', 'custom_reference_no'],
            );
            if (seResponse.statusCode == 200 &&
                seResponse.data['data'] != null) {
              for (var d in seResponse.data['data']) {
                _enrichmentCache[d['name']] = d;
              }
            }
          } catch (e) {
            if (kDebugMode) log('Error fetching SE details: $e');
          }
        }

        for (var i = 0; i < entries.length; i++) {
          final voucherNo = entries[i]['voucher_no'];
          if (voucherNo != null && _enrichmentCache.containsKey(voucherNo)) {
            entries[i].addAll(_enrichmentCache[voucherNo]!);
          }
        }

        stockLedgerEntries.value = entries;
      }
    } catch (e) {
      if (kDebugMode) log('Error fetching stock ledger: $e');
    } finally {
      isLoadingLedger.value = false;
    }
  }

  Future<void> fetchBatchHistory() async {
    isLoadingBatches.value = true;
    try {
      final response = await _provider.getBatchWiseHistory(itemCode);
      if (response.statusCode == 200&&
          response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        List<Map<String, dynamic>> historyList =
            data.whereType<Map<String, dynamic>>().toList();

        final batchIds = historyList
            .map((e) => e['batch_no'] ?? e['batch'])
            .where((val) => val != null && val.toString().isNotEmpty)
            .map((e) => e.toString())
            .toSet()
            .toList();

        if (batchIds.isNotEmpty) {
          try {
            final batchResponse = await _apiProvider.getDocumentList(
              'Batch',
              filters: {'name': ['in', batchIds]},
              fields: ['name', 'manufacturing_date', 'creation'],
              limit: batchIds.length,
            );
            if (batchResponse.statusCode == 200 &&
                batchResponse.data['data'] != null) {
              final batchDocs = batchResponse.data['data'] as List;
              final Map<String, String> dateMap = {};
              for (var b in batchDocs) {
                final mfgDate = b['manufacturing_date'] ?? b['creation'];
                if (mfgDate != null) dateMap[b['name']] = mfgDate;
              }
              for (var i = 0; i < historyList.length; i++) {
                final batchId =
                    historyList[i]['batch_no'] ?? historyList[i]['batch'];
                if (batchId != null && dateMap.containsKey(batchId)) {
                  historyList[i]['stock_age_date'] = dateMap[batchId];
                }
              }
            }
          } catch (e) {
            if (kDebugMode) log('Error fetching batch details: $e');
          }
        }

        batchHistory.value = historyList;
      }
    } catch (e) {
      if (kDebugMode) log('Error fetching batch history: $e');
    } finally {
      isLoadingBatches.value = false;
    }
  }

  String getFormattedStockAge(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date).inDays;
      if (difference < 30) return '$difference Days';
      int years = difference ~/ 365;
      int months = (difference % 365) ~/ 30;
      int days = (difference % 365) % 30;
      List<String> parts = [];
      if (years > 0) parts.add('$years Year${years > 1 ? 's' : ''}');
      if (months > 0) parts.add('$months Month${months > 1 ? 's' : ''}');
      if (days > 0) parts.add('$days Day${days > 1 ? 's' : ''}');
      return parts.join(', ');
    } catch (e) {
      return 'N/A';
    }
  }

  bool isImage(String? url) {
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  void copyToClipboard(String? text) {
    if (text == null || text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    GlobalSnackbar.success(message: 'Copied to clipboard');
  }

  void copyLink(String? relativeUrl) {
    if (relativeUrl == null) return;
    final fullUrl = '${_apiProvider.baseUrl}$relativeUrl';
    Clipboard.setData(ClipboardData(text: fullUrl));
    GlobalSnackbar.success(message: 'Link copied to clipboard');
  }

  Future<void> shareFile(String? relativeUrl, String? fileName) async {
    if (relativeUrl == null || fileName == null) return;
    final fullUrl = '${_apiProvider.baseUrl}$relativeUrl';

    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/$fileName';
      await Dio().download(fullUrl, savePath);
      if (Get.isDialogOpen == true) Get.back();
      await Share.shareXFiles([XFile(savePath)], text: 'Shared via Multimax ERP');
    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();
      Clipboard.setData(ClipboardData(text: fullUrl));
      GlobalSnackbar.info(
          title: 'Share Info',
          message: 'Could not download file. Link copied.');
    }
  }
}
