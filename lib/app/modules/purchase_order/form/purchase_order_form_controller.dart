import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/purchase_order_model.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_order_provider.dart';
import 'package:intl/intl.dart';

class PurchaseOrderFormController extends GetxController {
  final PurchaseOrderProvider _provider = Get.find<PurchaseOrderProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var purchaseOrder = Rx<PurchaseOrder?>(null);

  final supplierController = TextEditingController();
  final dateController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    if (mode == 'new') {
      _initNewPO();
    } else {
      fetchPO();
    }
  }

  @override
  void onClose() {
    supplierController.dispose();
    dateController.dispose();
    super.onClose();
  }

  void _initNewPO() {
    isLoading.value = false;
    final now = DateTime.now();
    purchaseOrder.value = PurchaseOrder(
      name: 'New Purchase Order',
      supplier: '',
      transactionDate: DateFormat('yyyy-MM-dd').format(now),
      grandTotal: 0.0,
      currency: 'AED',
      status: 'Draft',
      docstatus: 0,
      modified: '',
      creation: now.toString(),
      items: [],
    );
    dateController.text = DateFormat('yyyy-MM-dd').format(now);
  }

  Future<void> fetchPO() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseOrder(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final po = PurchaseOrder.fromJson(response.data['data']);
        purchaseOrder.value = po;
        supplierController.text = po.supplier;
        dateController.text = po.transactionDate;
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load PO: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> savePurchaseOrder() async {
    if (isSaving.value) return;
    isSaving.value = true;

    final data = {
      'supplier': supplierController.text,
      'transaction_date': dateController.text,
      'items': purchaseOrder.value?.items.map((e) => e.toJson()).toList(),
    };

    try {
      final response = mode == 'new'
          ? await _provider.createPurchaseOrder(data)
          : await _provider.updatePurchaseOrder(name, data);

      if (response.statusCode == 200) {
        Get.back();
        Get.snackbar('Success', 'Purchase Order Saved');
      } else {
        Get.snackbar('Error', 'Failed to save');
      }
    } catch (e) {
      Get.snackbar('Error', 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}