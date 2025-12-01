import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';

class PosUploadFormController extends GetxController {
  final PosUploadProvider _provider = Get.find<PosUploadProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var posUpload = Rx<PosUpload?>(null);

  // State for search and filtering
  var searchQuery = ''.obs;
  var filteredItems = <PosUploadItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    fetchPosUpload();
  }

  Future<void> fetchPosUpload() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPosUpload(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
        if (posUpload.value != null) {
          // Initialize the filtered list with all items
          filteredItems.assignAll(posUpload.value!.items);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch POS upload');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  void filterItems(String query) {
    searchQuery.value = query;
    if (query.isEmpty) {
      filteredItems.assignAll(posUpload.value?.items ?? []);
    } else {
      filteredItems.value = posUpload.value?.items
          .where((item) => item.itemName.toLowerCase().contains(query.toLowerCase()))
          .toList() ?? [];
    }
  }

  Future<void> updatePosUpload(Map<String, dynamic> data) async {
    isSaving.value = true;
    try {
      final response = await _provider.updatePosUpload(name, data);
      if (response.statusCode == 200) {
        Get.snackbar('Success', 'POS Upload updated successfully');
        // Refresh the data
        fetchPosUpload(); 
      } else {
        Get.snackbar('Error', 'Failed to update POS Upload');
      }
    } catch (e) {
      Get.snackbar('Error', 'Update failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
