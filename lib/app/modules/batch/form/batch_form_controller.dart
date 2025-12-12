// app/modules/batch/form/batch_form_controller.dart
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

  final itemController = TextEditingController();
  final descriptionController = TextEditingController();
  final mfgDateController = TextEditingController();
  final expDateController = TextEditingController();
  final packagingQtyController = TextEditingController();

  // Make Item Code read-only for existing batches (standard practice)
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
    packagingQtyController.dispose();
    super.onClose();
  }

  void _initNewBatch() {
    batch.value = Batch(
      name: 'New Batch',
      item: '',
      creation: '',
      modified: '',
    );
    isLoading.value = false;
  }

  Future<void> fetchBatch() async {
    isLoading.value = true;
    try {
      final response = await _provider.getBatch(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final b = Batch.fromJson(response.data['data']);
        batch.value = b;
        itemController.text = b.item;
        descriptionController.text = b.description ?? '';
        mfgDateController.text = b.manufacturingDate ?? '';
        expDateController.text = b.expiryDate ?? '';
        packagingQtyController.text = b.customPackagingQty.toString();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load batch: $e');
    } finally {
      isLoading.value = false;
    }
  }

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
      'custom_packaging_qty': double.tryParse(packagingQtyController.text) ?? 0.0,
    };

    try {
      if (isEditMode) {
        final response = await _provider.updateBatch(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch updated successfully');
          fetchBatch(); // Refresh
        } else {
          throw Exception(response.data['exception'] ?? 'Unknown Error');
        }
      } else {
        // Create new
        // Note: Batch ID (name) is usually auto-generated based on Naming Series or passed explicitly
        final response = await _provider.createBatch(data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Batch created successfully');
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