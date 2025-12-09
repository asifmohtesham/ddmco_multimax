import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_form_sheet.dart';

class PackingSlipFormController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  String name = Get.arguments['name']; // Not final to allow update on creation
  String mode = Get.arguments['mode']; // Not final to switch from new -> edit

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isScanning = false.obs;

  var packingSlip = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);

  final TextEditingController barcodeController = TextEditingController();

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  var bsMaxQty = 0.0.obs;
  var isEditing = false.obs; // Track if we are editing an existing row in PS

  // Temporary State for Item currently being added/edited
  String? currentItemDnDetail;
  String? currentItemCode;
  String? currentItemName;
  String? currentBatchNo;
  String? currentUom;
  String? currentSerial;
  double? currentNetWeight;
  double? currentWeightUom;
  String? currentItemNameKey; // The packing slip item row ID (null if new)

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
      log('Failed to fetch linked DN: $e');
    }
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    final item = linkedDeliveryNote.value!.items.firstWhereOrNull((element) => element.name == dnDetail);
    return item?.qty;
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    if (linkedDeliveryNote.value == null) {
      Get.snackbar('Error', 'Delivery Note not loaded yet. Please wait.');
      return;
    }

    isScanning.value = true;

    String itemCode;
    String? batchNo;

    // Barcode Parsing logic (EAN or EAN-BATCH)
    if (barcode.contains('-')) {
      final parts = barcode.split('-');
      final ean = parts.first;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = parts.join('-'); // Full string as batch usually, or just part 2? Assuming full logic
      // Actually standard logic: EAN is part 1, Batch is the rest.
      // If your batch format is specifically formatted, adjust here.
      // Reverting to simple split for safety based on provided controllers:
      batchNo = barcode;
    } else {
      final ean = barcode;
      itemCode = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo = null;
    }

    // Find matching item in Linked Delivery Note
    final match = _findItemInDN(itemCode, batchNo);

    isScanning.value = false;
    barcodeController.clear();

    if (match != null) {
      _prepareSheetForAdd(match);
    } else {
      Get.snackbar('Error', 'Item $itemCode not found in Delivery Note or Batch mismatch.');
    }
  }

  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    // Try exact match first
    return linkedDeliveryNote.value!.items.firstWhereOrNull((item) {
      bool codeMatch = item.itemCode == code;
      // If scanned has batch, it MUST match. If scanned doesn't, we can match any line
      // (usually implies prompting user, but for now match first available)
      bool batchMatch = (batch == null) || (item.batchNo == batch);
      return codeMatch && batchMatch;
    });
  }

  void _prepareSheetForAdd(DeliveryNoteItem item) {
    isEditing.value = false;
    currentItemNameKey = null; // New Item
    _populateItemDetails(item);

    // Calculate max allowed (Required - Already Packed in THIS slip)
    // Note: Ideally check across ALL slips, but for now checking this slip
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
      const PackingSlipItemFormSheet(),
      isScrollControlled: true,
    );
  }

  void editItem(PackingSlipItem item) {
    // Find original DN item to get max bounds
    final dnItem = linkedDeliveryNote.value?.items.firstWhereOrNull((d) => d.name == item.dnDetail);
    if (dnItem == null) return;

    isEditing.value = true;
    currentItemNameKey = item.name;
    _populateItemDetails(dnItem); // Re-populate static data from DN item

    // Calculate max: (Remaining + Current Item Qty)
    double existingPackedOthers = 0;
    for (var i in packingSlip.value!.items) {
      if (i.dnDetail == item.dnDetail && i.name != item.name) {
        existingPackedOthers += i.qty;
      }
    }
    bsMaxQty.value = dnItem.qty - existingPackedOthers;

    bsQtyController.text = item.qty.toStringAsFixed(0);

    Get.bottomSheet(
      const PackingSlipItemFormSheet(),
      isScrollControlled: true,
    );
  }

  void _populateItemDetails(DeliveryNoteItem item) {
    currentItemDnDetail = item.name;
    currentItemCode = item.itemCode;
    currentItemName = item.itemName;
    currentBatchNo = item.batchNo;
    currentUom = item.uom;
    currentSerial = item.customInvoiceSerialNumber;
    // Assuming net weight logic exists or defaults
    currentNetWeight = 0.0;
    currentWeightUom = 0.0;
  }

  void adjustQty(double delta) {
    double current = double.tryParse(bsQtyController.text) ?? 0;
    double newVal = current + delta;
    if (newVal < 0) newVal = 0;
    if (newVal > bsMaxQty.value) newVal = bsMaxQty.value;
    bsQtyController.text = newVal.toStringAsFixed(0);
  }

  Future<void> addItemToSlip() async {
    final double qtyToAdd = double.tryParse(bsQtyController.text) ?? 0;
    if (qtyToAdd <= 0) {
      Get.back();
      return;
    }

    final currentItems = packingSlip.value?.items.toList() ?? [];

    if (isEditing.value && currentItemNameKey != null) {
      // Update Existing
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PackingSlipItem(
            name: existing.name,
            dnDetail: existing.dnDetail,
            itemCode: existing.itemCode,
            itemName: existing.itemName,
            qty: qtyToAdd, // Updated Qty
            uom: existing.uom,
            batchNo: existing.batchNo,
            netWeight: existing.netWeight,
            weightUom: existing.weightUom,
            customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
            customVariantOf: existing.customVariantOf,
            customCountryOfOrigin: existing.customCountryOfOrigin,
            creation: existing.creation
        );
      }
    } else {
      // Add New
      // Check if exact same line exists (same dn_detail) to merge?
      // Usually packing slips list individually, but merging is cleaner if identical.
      final existingIndex = currentItems.indexWhere((i) => i.dnDetail == currentItemDnDetail);
      if (existingIndex != -1) {
        final existing = currentItems[existingIndex];
        currentItems[existingIndex] = PackingSlipItem(
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
      } else {
        final newItem = PackingSlipItem(
            name: '', // Empty for new
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
    }

    // Optimistic Update
    packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
    Get.back();

    // Save to Server
    await savePackingSlip();
  }

  Future<void> deleteCurrentItem() async {
    if (currentItemNameKey == null) return;

    Get.back(); // Close sheet

    Get.dialog(
        AlertDialog(
          title: const Text('Remove Item'),
          content: const Text('Are you sure you want to remove this item from the package?'),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Get.back(); // Close dialog
                final currentItems = packingSlip.value?.items.toList() ?? [];
                currentItems.removeWhere((i) => i.name == currentItemNameKey);
                packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
                await savePackingSlip();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove', style: TextStyle(color: Colors.white)),
            ),
          ],
        )
    );
  }

  Future<void> savePackingSlip() async {
    if (isSaving.value) return;
    isSaving.value = true;

    try {
      final docName = packingSlip.value?.name ?? '';
      final isNew = docName == 'New Packing Slip';

      final Map<String, dynamic> data = {
        'delivery_note': packingSlip.value!.deliveryNote,
        'from_case_no': packingSlip.value!.fromCaseNo,
        'to_case_no': packingSlip.value!.toCaseNo,
        'custom_po_no': packingSlip.value!.customPoNo,
        'items': packingSlip.value!.items.map((e) {
          final json = {
            'item_code': e.itemCode,
            'qty': e.qty,
            'dn_detail': e.dnDetail,
            // Add other fields if necessary
          };
          // Only send 'name' if it's not empty/new to update existing row
          if (e.name.isNotEmpty) json['name'] = e.name;
          return json;
        }).toList(),
      };

      final response = isNew
          ? await _apiProvider.createDocument('Packing Slip', data)
          : await _apiProvider.updateDocument('Packing Slip', docName, data);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = PackingSlip.fromJson(response.data['data']);
        packingSlip.value = saved;

        // If it was new, update the route args or name so next save is an update
        if (isNew) {
          name = saved.name;
          mode = 'edit';
          Get.snackbar('Success', 'Packing Slip Created: ${saved.name}');
        } else {
          Get.snackbar('Success', 'Packing Slip Saved');
        }
      } else {
        Get.snackbar('Error', 'Failed to save Packing Slip');
      }
    } catch (e) {
      Get.snackbar('Error', 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}