import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';

class ItemFormController extends GetxController with OptimisticLockingMixin {
  final String docType = 'Item';
  final ItemProvider _provider = Get.find<ItemProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

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

  // ── Auto re-order ─────────────────────────────────────────────────────────
  /// Working copy of `Item.reorder_levels`, seeded on every successful fetch.
  var reorderRows = <ItemReorder>[].obs;

  /// True while [saveReorderLevels] is in flight.
  var isSavingReorder = false.obs;

  /// True when [reorderRows] differs from the last-fetched state.
  var isReorderDirty = false.obs;

  /// Mirrors `Stock Settings.auto_indent`. Defaults to **true** so the warning
  /// banner stays hidden until we positively learn the setting is off — a
  /// permission error must not produce a false alarm.
  var autoIndentEnabled = true.obs;

  /// JSON snapshot of [reorderRows] taken after each successful fetch, so the
  /// dirty flag is a diff rather than a one-way latch (reverting an edit
  /// clears it). Mirrors the DN/PO/PS/ToDo form controllers.
  String _originalReorderJson = '';

  bool _reorderTabLoaded = false;
  // ──────────────────────────────────────────────────────────────────────────

  /// Batch No from the last scan that opened this sheet. Null when the item
  /// was opened without batch context (e.g. by tapping a list row).
  var highlightedBatchNo = RxnString();

  static bool isBatchHighlighted(String batchNo, String? highlightedBatchNo) {
    if (highlightedBatchNo == null || batchNo == 'N/A') return false;
    return batchNo == highlightedBatchNo;
  }

  // ── Warehouse filter ──────────────────────────────────────────────────────
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
  // ──────────────────────────────────────────────────────────────────────────

  bool _stockTabLoaded = false;
  bool _attachmentsTabLoaded = false;

  final Map<String, Map<String, dynamic>> _enrichmentCache = {};

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      if (args is Map && args['itemCode'] != null) {
        itemCode = args['itemCode'];
        highlightedBatchNo.value = args['batchNo'] as String?;
        _loadCoreData();
      } else if (args is String) {
        itemCode = args;
        _loadCoreData();
      }
    }
  }

  /// Called by [ItemTabController]'s tab listener on every settled
  /// tab-index change.  Triggers lazy data loads for Stock and Attachments
  /// tabs the first time they are visited.
  void onTabChanged(int index) {
    switch (index) {
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
      case 4:
        if (!_reorderTabLoaded) {
          _reorderTabLoaded = true;
          fetchAutoIndentSetting();
        }
        break;
    }
  }

  void loadItem(String code, {String? batchNo}) {
    itemCode = code;
    highlightedBatchNo.value = batchNo;
    // Reset lazy-load flags so every fresh open of the sheet reloads
    // Stock and Attachments tabs when visited for the first time.
    _stockTabLoaded = false;
    _attachmentsTabLoaded = false;
    _reorderTabLoaded = false;
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
        _seedReorderRows();
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
      if (response.statusCode == 200 &&
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

  // ── Auto re-order ─────────────────────────────────────────────────────────

  @override
  Future<void> reloadDocument() async {
    await fetchItemDetails();
  }

  String _reorderJson(List<ItemReorder> rows) =>
      jsonEncode(rows.map((r) => r.toJson()).toList());

  void _seedReorderRows() {
    reorderRows.value =
        List<ItemReorder>.from(item.value?.reorderLevels ?? const []);
    _originalReorderJson = _reorderJson(reorderRows);
    isReorderDirty.value = false;
  }

  void _checkReorderDirty() {
    isReorderDirty.value = _reorderJson(reorderRows) != _originalReorderJson;
  }

  /// A blank row seeded with the item's default request type.
  ItemReorder newReorderRowTemplate() => ItemReorder(
        warehouse: '',
        materialRequestType:
            defaultReorderTypeFor(item.value?.defaultMaterialRequestType),
      );

  void addReorderRow(ItemReorder row) {
    reorderRows.add(row);
    _checkReorderDirty();
  }

  void updateReorderRow(int index, ItemReorder row) {
    if (index < 0 || index >= reorderRows.length) return;
    reorderRows[index] = row;
    _checkReorderDirty();
  }

  void removeReorderRow(int index) {
    if (index < 0 || index >= reorderRows.length) return;
    reorderRows.removeAt(index);
    _checkReorderDirty();
  }

  /// Reads `Stock Settings.auto_indent`.
  ///
  /// **Fails open by design.** Reading the Stock Settings Single needs
  /// permission on that doctype and the resource API 403s for non-System
  /// Managers. On any error [autoIndentEnabled] is left `true`, so the warning
  /// banner is simply not shown rather than shown wrongly.
  Future<void> fetchAutoIndentSetting() async {
    try {
      final response = await _provider.getStockSettings();
      if (response.statusCode == 200 && response.data?['data'] != null) {
        final v = response.data['data']['auto_indent'];
        autoIndentEnabled.value = v == 1 || v == true || v == '1';
      }
    } catch (e) {
      if (kDebugMode) log('Could not read Stock Settings.auto_indent: $e');
    }
  }

  /// Extracts a human-readable message from a Frappe error body.
  ///
  /// Frappe returns validation throws in `_server_messages` — a JSON-encoded
  /// list of JSON-encoded maps each carrying a `message`. The reorder
  /// descendant check (item.py:523-534) arrives this way, and its text is
  /// specific enough to be worth surfacing verbatim rather than replacing with
  /// a generic string. Public and static so it is unit-testable directly.
  static String parseServerMessage(dynamic data) {
    if (data is! Map) return 'Save failed';

    final raw = data['_server_messages'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) {
          final messages = <String>[];
          for (final entry in decoded) {
            final m = entry is String ? jsonDecode(entry) : entry;
            final text = m is Map ? m['message'] : null;
            if (text != null) messages.add(text.toString());
          }
          if (messages.isNotEmpty) {
            // Frappe embeds <b>/<br> in throw messages.
            return messages
                .join('\n')
                .replaceAll(RegExp(r'<br\s*/?>'), '\n')
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim();
          }
        }
      } catch (_) {
        // Malformed payload — fall through to the exception key.
      }
    }

    if (data['exception'] != null) {
      return data['exception'].toString().split(':').last.trim();
    }
    return 'Save failed';
  }

  /// Writes [reorderRows] back to `Item.reorder_levels`.
  ///
  /// The full array is sent: Frappe replaces the child table wholesale, so an
  /// omitted row is deleted. Existing rows carry their `name` and are updated
  /// in place; new rows omit it and are inserted.
  Future<void> saveReorderLevels() async {
    if (isSavingReorder.value) return;

    final error = validateReorderRows(reorderRows);
    if (error != null) {
      GlobalSnackbar.error(message: error);
      return;
    }
    if (checkStaleAndBlock()) return;

    isSavingReorder.value = true;

    final data = <String, dynamic>{
      'reorder_levels': reorderRows.map((r) => r.toJson()).toList(),
      'modified': item.value?.modified,
    };

    try {
      final response = await _provider.updateReorderLevels(itemCode, data);
      if (response.statusCode == 200) {
        // Reseeds rows and the dirty baseline from the server's own version,
        // which includes any warehouse_group the server defaulted for us.
        await fetchItemDetails();
        GlobalSnackbar.success(message: 'Re-order rules saved');
      } else {
        GlobalSnackbar.error(message: 'Failed to save re-order rules');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: parseServerMessage(e.response?.data));
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSavingReorder.value = false;
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

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
