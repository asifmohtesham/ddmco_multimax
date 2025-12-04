import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/purchase_receipt_model.dart';
import 'package:ddmco_multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  // Form Fields
  final supplierController = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  var setWarehouse = RxnString();
  
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchPurchaseReceipt();
    }
  }

  @override
  void onClose() {
    supplierController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    super.onClose();
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  void _initNewPurchaseReceipt() {
    isLoading.value = true;
    final now = DateTime.now();
    final purchaseOrder = Get.arguments['purchaseOrder'] ?? '';
    final supplier = Get.arguments['supplier'] ?? '';

    purchaseReceipt.value = PurchaseReceipt(
      name: 'New Purchase Receipt',
      supplier: supplier,
      grandTotal: 0.0,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      currency: 'USD', // Default or from settings
      items: [],
    );

    supplierController.text = supplier;
    postingDateController.text = DateFormat('yyyy-MM-dd').format(now);
    postingTimeController.text = DateFormat('HH:mm:ss').format(now);
    
    isLoading.value = false;
  }

  Future<void> fetchPurchaseReceipt() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        purchaseReceipt.value = receipt;
        
        supplierController.text = receipt.supplier;
        postingDateController.text = receipt.postingDate;
        // time?
      } else {
        Get.snackbar('Error', 'Failed to fetch purchase receipt');
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
