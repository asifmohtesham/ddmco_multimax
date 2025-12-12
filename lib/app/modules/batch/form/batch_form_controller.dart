// app/modules/batch/form/batch_form_controller.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/batch_model.dart';
import 'package:multimax/app/data/providers/batch_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:intl/intl.dart';

class BatchFormController extends GetxController {
  final BatchProvider _provider = Get.find<BatchProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var batch = Rx<Batch?>(null);

  // Form Controllers
  final itemController = TextEditingController();
  final descriptionController = TextEditingController();
  final mfgDateController = TextEditingController();
  final expDateController = TextEditingController();
  final customPackagingQtyController = TextEditingController();
  final customPurchaseOrderController = TextEditingController();

  // New State
  var generatedBatchId = ''.obs;
  var itemBarcode = ''.obs;

  // Selection Lists
  var isFetchingItems = false.obs;
  var itemList = <Map<String, dynamic>>[].obs;

  var isFetchingPOs = false.obs;
  var poList = <Map<String, dynamic>>[].obs;

  bool get isEditMode => mode == 'edit';

  @override
  void onInit() {
    super.onInit();
    if (isEditMode) {
      fetchBatch();
    } else {
      _initNewBatch();
    }
  }

  @override
  void onClose() {
    itemController.dispose();
    descriptionController.dispose();
    mfgDateController.dispose();
    expDateController.dispose();
    customPackagingQtyController.dispose();
    customPurchaseOrderController.dispose();
    super.onClose();
  }

  void _initNewBatch() {
    batch.value = Batch(
      name: 'New Batch',
      item: '',
      creation: '',
      modified: '',
    );

    // Default Values
    mfgDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    customPackagingQtyController.text = '12';

    isLoading.value = false;
  }

  Future<void> fetchBatch() async {
    isLoading.value = true;
    try {
      final response = await _provider.getBatch(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final b = Batch.fromJson(response.data['data']);
        batch.value = b;

        // Populate Fields
        itemController.text = b.item;
        descriptionController.text = b.description ?? '';
        mfgDateController.text = b.manufacturingDate ?? '';
        expDateController.text = b.expiryDate ?? '';
        customPackagingQtyController.text = b.customPackagingQty.toString();
        customPurchaseOrderController.text = b.customPurchaseOrder ?? '';
        generatedBatchId.value = b.name;

        // Fetch item details to show barcode if editing
        if(b.item.isNotEmpty) {
          _fetchItemDetails(b.item, generateId: false);
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load batch: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- Search & Selection Logic ---

  Future<void> searchItems(String query) async {
    isFetchingItems.value = true;
    try {
      final response = await _provider.searchItems(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        itemList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      print(e);
    } finally {
      isFetchingItems.value = false;
    }
  }

  Future<void> searchPurchaseOrders(String query) async {
    isFetchingPOs.value = true;
    try {
      final response = await _provider.searchPurchaseOrders(query);
      if (response.statusCode == 200 && response.data['data'] != null) {
        poList.assignAll(List<Map<String, dynamic>>.from(response.data['data']));
      }
    } catch (e) {
      print(e);
    } finally {
      isFetchingPOs.value = false;
    }
  }

  void selectItem(Map<String, dynamic> itemData) {
    itemController.text = itemData['item_code'];
    Get.back(); // Close sheet
    _fetchItemDetails(itemData['item_code'], generateId: true);
  }

  void selectPurchaseOrder(String poName) {
    customPurchaseOrderController.text = poName;
    Get.back();
  }

  Future<void> _fetchItemDetails(String itemCode, {bool generateId = false}) async {
    try {
      final response = await _provider.getItemDetails(itemCode);
      if(response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];

        // Extract Barcode (Assuming 'barcodes' child table or 'barcode' field)
        String barcode = '';
        if (data['barcodes'] != null && (data['barcodes'] as List).isNotEmpty) {
          barcode = data['barcodes'][0]['barcode'] ?? '';
        } else if (data['barcode'] != null) {
          barcode = data['barcode'];
        } else {
          // Fallback to Item Code if no EAN
          barcode = itemCode;
        }

        itemBarcode.value = barcode;

        if (generateId && !isEditMode) {
          _generateBatchId(barcode);
        }
      }
    } catch (e) {
      print('Error fetching item details: $e');
    }
  }

  void _generateBatchId(String ean) {
    // Generate Random 6-char String (Alphanumeric)
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed I, 1, 0, O for clarity
    final rnd = Random();
    final randomId = String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));

    generatedBatchId.value = '$ean-$randomId';
  }

  // --- Save Logic ---

  Future<void> saveBatch() async {
    if (itemController.text.isEmpty) {
      GlobalSnackbar.warning(message: 'Item Code is required');
      return;
    }

    isSaving.value = true;
    final data = {
      'item': itemController.text,
      'description': descriptionController.text,
      'manufacturing_date': mfgDateController.text.isEmpty ? null : mfgDateController.text,
      'expiry_date': expDateController.text.isEmpty ? null : expDateController.text,
      'custom_packaging_qty': double.tryParse(customPackagingQtyController.text) ?? 0.0,
      'purchase_order': customPurchaseOrderController.text.isEmpty ? null : customPurchaseOrderController.text,
    };

    try {
      if (isEditMode) {
        final response = await _provider.updateBatch(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch updated successfully');
          fetchBatch();
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      } else {
        // Explicitly set the name (Batch ID) for new documents if API allows manual naming
        data['batch_id'] = generatedBatchId.value; // ERPNext often uses 'batch_id' or 'name' depending on naming series
        data['name'] = generatedBatchId.value; // Attempt to force name

        final response = await _provider.createBatch(data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch created: ${generatedBatchId.value}');
          Get.back(result: true);
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> pickDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }
}