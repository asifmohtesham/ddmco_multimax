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
  var stockLevels = <WarehouseStock>[].obs;
  var isLoadingStock = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchItemDetails();
    fetchAttachments();
    fetchStockLevels();
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

  Future<void> fetchStockLevels() async {
    isLoadingStock.value = true;
    try {
      final response = await _provider.getStockLevels(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> data = response.data['message']['result'];
        // Handle the map based JSON from report
        stockLevels.value = data.map((json) => WarehouseStock.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching stock levels: $e');
    } finally {
      isLoadingStock.value = false;
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

    // Show loading overlay
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      // 1. Get Temporary Directory
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/$fileName';

      // 2. Download File
      // Note: If files are private, we might need to attach cookies from ApiProvider.
      // For now, using basic Dio download.
      await Dio().download(fullUrl, savePath);

      // Close loading overlay
      if (Get.isDialogOpen == true) Get.back();

      // 3. Share File
      await Share.shareXFiles([XFile(savePath)], text: 'Shared via Multimax ERP');

    } catch (e) {
      if (Get.isDialogOpen == true) Get.back();

      // Fallback: Copy Link if download fails or Share plugin missing
      Clipboard.setData(ClipboardData(text: fullUrl));
      Get.snackbar(
          'Share Info',
          'Could not download file directly. Link copied to clipboard.',
          duration: const Duration(seconds: 3)
      );
      print('Share Error: $e');
    }
  }
}