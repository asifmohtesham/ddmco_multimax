import 'dart:io';
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

class ItemFormController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  String itemCode = '';
  var item = Rx<Item?>(null);
  var isLoading = true.obs;

  var attachments = <Map<String, dynamic>>[].obs;

  // Dashboard Data
  var stockLevels = <WarehouseStock>[].obs;
  var stockLedgerEntries = <Map<String, dynamic>>[].obs;
  var batchHistory = <Map<String, dynamic>>[].obs;

  var isLoadingStock = false.obs;
  var isLoadingLedger = false.obs;
  var isLoadingBatches = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Support standard navigation arguments
    if (Get.arguments != null && Get.arguments is Map && Get.arguments['itemCode'] != null) {
      itemCode = Get.arguments['itemCode'];
      _loadAllData();
    }
  }

  // New method to load data manually (for Bottom Sheet usage)
  void loadItem(String code) {
    itemCode = code;
    _loadAllData();
  }

  void _loadAllData() {
    fetchItemDetails();
    fetchAttachments();
    fetchDashboardData();
  }

  Future<void> fetchItemDetails() async {
    if (itemCode.isEmpty) return;
    isLoading.value = true;
    try {
      // Use getDocument to ensure we get child tables (Attributes)
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
      final response = await _apiProvider.getDocumentList('File', filters: {
        'attached_to_doctype': 'Item',
        'attached_to_name': itemCode,
      }, fields: ['file_name', 'file_url', 'is_private']);

      if (response.statusCode == 200 && response.data['data'] != null) {
        attachments.value = List<Map<String, dynamic>>.from(response.data['data']);
      }
    } catch (e) {
      print('Error fetching attachments: $e');
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
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        stockLevels.value = data.whereType<Map<String, dynamic>>().map((json) => WarehouseStock.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching stock levels: $e');
    } finally {
      isLoadingStock.value = false;
    }
  }

  Future<void> fetchStockLedger() async {
    isLoadingLedger.value = true;
    try {
      final response = await _provider.getStockLedger(itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        List<Map<String, dynamic>> entries = List<Map<String, dynamic>>.from(response.data['data']);

        // --- Enrichment Logic ---
        final List<String> dnNames = [];
        final List<String> seNames = [];

        for (var entry in entries) {
          final type = entry['voucher_type'];
          final no = entry['voucher_no'];
          if (type == 'Delivery Note' && no != null) dnNames.add(no);
          if (type == 'Stock Entry' && no != null) seNames.add(no);
        }

        Map<String, Map<String, dynamic>> extraDetails = {};

        if (dnNames.isNotEmpty) {
          try {
            final dnResponse = await _apiProvider.getDocumentList(
                'Delivery Note',
                filters: {'name': ['in', dnNames]},
                fields: ['name', 'customer', 'po_no']
            );
            if (dnResponse.statusCode == 200 && dnResponse.data['data'] != null) {
              for (var d in dnResponse.data['data']) {
                extraDetails[d['name']] = d;
              }
            }
          } catch (e) { print('Error fetching DN details: $e'); }
        }

        if (seNames.isNotEmpty) {
          try {
            final seResponse = await _apiProvider.getDocumentList(
                'Stock Entry',
                filters: {'name': ['in', seNames]},
                fields: ['name', 'stock_entry_type', 'custom_reference_no']
            );
            if (seResponse.statusCode == 200 && seResponse.data['data'] != null) {
              for (var d in seResponse.data['data']) {
                extraDetails[d['name']] = d;
              }
            }
          } catch (e) { print('Error fetching SE details: $e'); }
        }

        // Merge details back into entries
        for (var i = 0; i < entries.length; i++) {
          final voucherNo = entries[i]['voucher_no'];
          if (extraDetails.containsKey(voucherNo)) {
            entries[i].addAll(extraDetails[voucherNo]!);
          }
        }
        // ------------------------

        stockLedgerEntries.value = entries;
      }
    } catch (e) {
      print('Error fetching stock ledger: $e');
    } finally {
      isLoadingLedger.value = false;
    }
  }

  Future<void> fetchBatchHistory() async {
    isLoadingBatches.value = true;
    try {
      final response = await _provider.getBatchWiseHistory(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        batchHistory.value = data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      print('Error fetching batch history: $e');
    } finally {
      isLoadingBatches.value = false;
    }
  }

  bool isImage(String? url) {
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
  }

  void copyLink(String? relativeUrl) {
    if (relativeUrl == null) return;
    final fullUrl = 'https://erp.multimax.cloud$relativeUrl';
    Clipboard.setData(ClipboardData(text: fullUrl));
    GlobalSnackbar.success(message: 'Link copied to clipboard');
  }

  Future<void> shareFile(String? relativeUrl, String? fileName) async {
    if (relativeUrl == null || fileName == null) return;
    final fullUrl = 'https://erp.multimax.cloud$relativeUrl';

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
      GlobalSnackbar.info(title: 'Share Info', message: 'Could not download file. Link copied.');
    }
  }
}