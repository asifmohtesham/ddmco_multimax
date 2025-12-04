import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:ddmco_multimax/app/data/models/packing_slip_model.dart';
import 'package:ddmco_multimax/app/data/providers/packing_slip_provider.dart';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/form/packing_slip_form_screen.dart'; // Import for bottom sheet

class PackingSlipFormController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  
  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode']; 

  var isLoading = true.obs;
  var isScanning = false.obs;
  var packingSlip = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);

  final TextEditingController barcodeController = TextEditingController();

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  var bsMaxQty = 0.0.obs;
  String? currentItemDnDetail;
  String? currentItemCode;
  String? currentItemName;
  String? currentBatchNo;
  String? currentUom;
  String? currentSerial;

  @override
  void onInit() {
    super.onInit();
    if (mode == 'new') {
      _initNewPackingSlip();
    } else {
      fetchPackingSlip();
    }
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    super.onClose();
  }

  void _initNewPackingSlip() {
    isLoading.value = true;
    final String dnName = Get.arguments['deliveryNote'] ?? '';
    final String? customPoNo = Get.arguments['customPoNo'];
    final int nextCaseNo = Get.arguments['nextCaseNo'] ?? 1;

    packingSlip.value = PackingSlip(
      name: 'New Packing Slip',
      deliveryNote: dnName,
      modified: '',
      creation: DateTime.now().toString(),
      docstatus: 0,
      status: 'Draft',
      customPoNo: customPoNo,
      fromCaseNo: nextCaseNo,
      toCaseNo: nextCaseNo, 
      items: [],
    );

    if (dnName.isNotEmpty) {
      fetchLinkedDeliveryNote(dnName);
    }
    isLoading.value = false;
  }

  Future<void> fetchPackingSlip() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPackingSlip(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final slip = PackingSlip.fromJson(response.data['data']);
        packingSlip.value = slip;
        
        if (slip.deliveryNote.isNotEmpty) {
          await fetchLinkedDeliveryNote(slip.deliveryNote);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch packing slip details');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load data: ${e.toString()}');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchLinkedDeliveryNote(String dnName) async {
    try {
      final response = await _dnProvider.getDeliveryNote(dnName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        linkedDeliveryNote.value = DeliveryNote.fromJson(response.data['data']);
      }
    } catch (e) {
      print('Failed to fetch linked DN: $e');
    }
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    final item = linkedDeliveryNote.value!.items.firstWhereOrNull((element) => element.name == dnDetail);
    return item?.qty;
  }

  Future<void> scanBarcode(String barcode) async {
    if (linkedDeliveryNote.value == null) {
      Get.snackbar('Error', 'Delivery Note not loaded yet');
      return;
    }

    isScanning.value = true;
    
    String itemCode;
    String? batchNo;

    if (barcode.contains('-')) {
      final parts = barcode.split('-');
      final ean = parts.first;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = parts.join('-');
    } else {
      final ean = barcode;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = null;
    }

    final match = _findItemInDN(itemCode, batchNo);

    isScanning.value = false;
    barcodeController.clear();

    if (match != null) {
      _openQtySheet(match);
    } else {
      Get.snackbar('Error', 'Item not found in Delivery Note or Batch mismatch');
    }
  }

  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    return linkedDeliveryNote.value!.items.firstWhereOrNull((item) {
      bool codeMatch = item.itemCode == code;
      bool batchMatch = (batch == null) || (item.batchNo == batch);
      return codeMatch && batchMatch;
    });
  }

  void _openQtySheet(DeliveryNoteItem item) {
    currentItemDnDetail = item.name;
    currentItemCode = item.itemCode;
    currentItemName = item.itemName;
    currentBatchNo = item.batchNo;
    currentUom = item.uom;
    currentSerial = item.customInvoiceSerialNumber;

    double existingPacked = 0;
    final currentSlipItems = packingSlip.value?.items ?? [];
    for (var i in currentSlipItems) {
      if (i.dnDetail == item.name) {
        existingPacked += i.qty;
      }
    }
    
    double remaining = item.qty - existingPacked;
    if (remaining < 0) remaining = 0;

    bsMaxQty.value = remaining;
    bsQtyController.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';

    Get.bottomSheet(
      const PackingItemQtySheet(),
      isScrollControlled: true,
    );
  }

  void addItemToSlip() {
    final double qtyToAdd = double.tryParse(bsQtyController.text) ?? 0;
    if (qtyToAdd <= 0) {
      Get.back();
      return;
    }

    final currentItems = packingSlip.value?.items.toList() ?? [];
    
    final existingIndex = currentItems.indexWhere((i) => i.dnDetail == currentItemDnDetail);
    
    if (existingIndex != -1) {
       final existing = currentItems[existingIndex];
       final updated = PackingSlipItem(
         name: existing.name,
         dnDetail: existing.dnDetail,
         itemCode: existing.itemCode,
         itemName: existing.itemName,
         qty: existing.qty + qtyToAdd,
         uom: existing.uom,
         batchNo: existing.batchNo,
         netWeight: existing.netWeight, 
         weightUom: existing.weightUom,
         customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
         customVariantOf: existing.customVariantOf,
         customCountryOfOrigin: existing.customCountryOfOrigin,
         creation: existing.creation
       );
       currentItems[existingIndex] = updated;
    } else {
       final newItem = PackingSlipItem(
         name: '', 
         dnDetail: currentItemDnDetail!,
         itemCode: currentItemCode!,
         itemName: currentItemName ?? '',
         qty: qtyToAdd,
         uom: currentUom ?? '',
         batchNo: currentBatchNo ?? '',
         netWeight: 0.0, 
         weightUom: 0.0,
         customInvoiceSerialNumber: currentSerial,
         customVariantOf: null, 
         customCountryOfOrigin: null, 
         creation: DateTime.now().toString()
       );
       currentItems.add(newItem);
    }

    packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
    Get.back();
    Get.snackbar('Success', 'Item added to Packing Slip');
  }
}
