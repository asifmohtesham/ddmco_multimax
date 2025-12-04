
import 'dart:developer';

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
    
    // Parse barcode
    // Format: EAN or EAN-BATCH
    // Assuming simple split by '-' if batch is appended, or regex match
    String itemCode = barcode;
    String? batchNo;
    
    final RegExp batchRegex = RegExp(r'^(\d+)-([a-zA-Z0-9]+)$'); // Example pattern
    if (barcode.contains('-')) {
        // Simple logic for now, adjust based on actual barcode format
        // If strict EAN is 13 digits, check length?
        // Let's assume standard behavior: try to match whole barcode to item_code first.
        // If not found, try split.
    }
    
    // 1. Try direct match on item_code in DN items
    var match = _findItemInDN(barcode, null);
    
    if (match == null && barcode.contains('-')) {
       // 2. Try parsing batch
       final parts = barcode.split('-');
       // Assuming last part is batch, rest is item code? Or defined structure?
       // Let's assume ItemCode-BatchNo
       itemCode = parts[0].substring(0,7);
       batchNo = parts.join('-');
       match = _findItemInDN(itemCode, batchNo);
    }

    isScanning.value = false;
    barcodeController.clear();

    if (match != null) {
      // Found valid item in DN
      _openQtySheet(match);
    } else {
      Get.snackbar('Error', 'Item not found in Delivery Note or Batch mismatch');
    }
  }

  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    return linkedDeliveryNote.value!.items.firstWhereOrNull((item) {
      bool codeMatch = item.itemCode == code || (item.name != null && item.name == code); // Check item_code or ID? Usually item_code.
      // Or check barcode field if available (not in model currently, assuming scan item_code directly)

      bool batchMatch = true;
      if (batch != null && batch.isNotEmpty) {
        batchMatch = item.batchNo == batch;
      }
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

    // Calculate remaining qty
    // Total in DN - Already Packed in THIS slip (and ideally others, but let's stick to this one first or calculate globally if we fetched all slips)
    // For simplicity, default to remaining unpacked in *this* slip logic? 
    // Or just default to 1 or item.qty.
    // The requirement says "populating".
    
    // Check if we already have this item in the packing slip to update it?
    // Usually packing slip items are unique per package or accumulated.
    // If we pack into the *same* package (this document), we might merge.
    
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
    bsQtyController.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0'; // Default to max possible

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

    // Add to list
    final currentItems = packingSlip.value?.items.toList() ?? [];
    
    // Check if item with same dnDetail exists in this slip to merge?
    // Packing Slip Item usually distinct rows or merged? 
    // Let's merge if same item/batch/etc.
    
    final existingIndex = currentItems.indexWhere((i) => i.dnDetail == currentItemDnDetail);
    
    if (existingIndex != -1) {
       // Merge
       final existing = currentItems[existingIndex];
       final updated = PackingSlipItem(
         name: existing.name, // Keep ID if exists
         dnDetail: existing.dnDetail,
         itemCode: existing.itemCode,
         itemName: existing.itemName,
         qty: existing.qty + qtyToAdd,
         uom: existing.uom,
         batchNo: existing.batchNo,
         netWeight: existing.netWeight, // Should recalc weight
         weightUom: existing.weightUom,
         customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
         customVariantOf: existing.customVariantOf,
         customCountryOfOrigin: existing.customCountryOfOrigin,
         creation: existing.creation
       );
       currentItems[existingIndex] = updated;
    } else {
       // Add new
       final newItem = PackingSlipItem(
         name: '', // New, no ID yet
         dnDetail: currentItemDnDetail!,
         itemCode: currentItemCode!,
         itemName: currentItemName ?? '',
         qty: qtyToAdd,
         uom: currentUom ?? '',
         batchNo: currentBatchNo ?? '',
         netWeight: 0.0, // Needs logic
         weightUom: 0.0,
         customInvoiceSerialNumber: currentSerial,
         // Mapping other fields from DN item? 
         // Model doesn't store them all on item, but we can if needed. 
         // For now fill basics.
         customVariantOf: null, 
         customCountryOfOrigin: null, 
         creation: DateTime.now().toString()
       );
       currentItems.add(newItem);
    }

    packingSlip.value = packingSlip.value?.copyWith(items: currentItems); // Need copyWith on PackingSlip
    Get.back();
    Get.snackbar('Success', 'Item added to Packing Slip');
    
    // TODO: Save to API if in edit mode, or just local state if 'new'.
    // User flow implies building it locally first?
  }
}
