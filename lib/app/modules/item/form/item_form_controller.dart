import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/item_model.dart';
import 'package:ddmco_multimax/app/data/providers/item_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';

class ItemFormController extends GetxController {
  final ItemProvider _provider = Get.find<ItemProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String itemCode = Get.arguments['itemCode'];
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
    fetchItemDetails();
    fetchAttachments();
    fetchDashboardData();
  }

  Future<void> fetchItemDetails() async {
    isLoading.value = true;
    try {
      final response = await _provider.getItems(limit: 1, filters: {'item_code': itemCode});
      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        item.value = Item.fromJson(response.data['data'][0]);
      } else {
        Get.snackbar('Error', 'Item not found');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchAttachments() async {
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
        stockLedgerEntries.value = List<Map<String, dynamic>>.from(response.data['data']);
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
        // Filter out rows that might be headers or empty if the report structure varies
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
    Get.snackbar('Success', 'Link copied to clipboard');
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
      Get.snackbar('Share Info', 'Could not download file. Link copied.', duration: const Duration(seconds: 3));
    }
  }
}