import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/storage_service.dart';

class PackingSlipFormController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StorageService _storageService = Get.find<StorageService>();

  var itemFormKey = GlobalKey<FormState>();
  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isScanning = false.obs;

  var isDirty = false.obs;
  String _originalJson = '';

  var isSheetValid = false.obs;
  String _initialQty = '';

  var packingSlip = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  // Other Packing Slips linked to the same Delivery Note (for progress calculation)
  var relatedPackingSlips = <PackingSlip>[].obs;

  final TextEditingController barcodeController = TextEditingController();

  var expandedInvoice = ''.obs;

  final bsQtyController = TextEditingController();
  var bsMaxQty = 0.0.obs;
  var isEditing = false.obs;

  // Filters
  var itemFilter = 'All'.obs;

  // Track Sheet Open State
  var isItemSheetOpen = false.obs;

  // Temporary State
  String? currentItemDnDetail;
  String? currentItemCode;
  String? currentItemName;
  String? currentBatchNo;
  String? currentUom;
  String? currentSerial;
  double? currentNetWeight;
  double? currentWeightUom;
  String? currentItemNameKey;

  // Metadata Observables
  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModified = RxnString();
  var bsItemModifiedBy = RxnString();

  Timer? _autoSubmitTimer;

  @override
  void onInit() {
    super.onInit();
    bsQtyController.addListener(validateSheet);

    // Auto-Submit Logic
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();

      if (valid && isItemSheetOpen.value && packingSlip.value?.docstatus == 0) {
        if (_storageService.getAutoSubmitEnabled()) {
          final int delay = _storageService.getAutoSubmitDelay();
          _autoSubmitTimer = Timer(Duration(seconds: delay), () {
            // Re-validate strictly before submission
            if (isSheetValid.value && isItemSheetOpen.value) {
              addItemToSlip();
            }
          });
        }
      }
    });

    if (mode == 'new') {
      _initNewPackingSlip();
    } else {
      fetchPackingSlip();
    }
  }

  @override
  void onClose() {
    _autoSubmitTimer?.cancel();
    barcodeController.dispose();
    bsQtyController.dispose();
    super.onClose();
  }

  // --- PopScope Logic ---
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false; // Reset dirty flag
        Get.back(); // Pop the screen (Navigation)
      },
    );
  }

  void validateSheet() {
    final text = bsQtyController.text;
    final qty = double.tryParse(text);

    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }

    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    if (isEditing.value) {
      if (text == _initialQty) {
        isSheetValid.value = false;
        return;
      }
    }

    isSheetValid.value = true;
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
      customer: '',
    );
    isDirty.value = true;
    _originalJson = '';
    if (dnName.isNotEmpty) {
      fetchLinkedDeliveryNote(dnName);
      fetchRelatedPackingSlips(dnName);
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
        _updateOriginalState(slip);
        if (slip.deliveryNote.isNotEmpty) {
          await fetchLinkedDeliveryNote(slip.deliveryNote);
          fetchRelatedPackingSlips(slip.deliveryNote);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch packing slip details');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load data: ${e.toString()}');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchLinkedDeliveryNote(String dnName) async {
    try {
      final response = await _dnProvider.getDeliveryNote(dnName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final dn = DeliveryNote.fromJson(response.data['data']);
        linkedDeliveryNote.value = dn;

        // Fetch POS Upload if available
        if (dn.poNo != null && dn.poNo!.isNotEmpty) {
          fetchPosUpload(dn.poNo!);
        }

        if (packingSlip.value != null && (packingSlip.value!.customer == null || packingSlip.value!.customer!.isEmpty)) {
          packingSlip.value = packingSlip.value!.copyWith(customer: dn.customer);
          // If we auto-corrected the customer on load, treat this as the new "original" state
          if (mode != 'new') _updateOriginalState(packingSlip.value!);
        }
      }
    } catch (e) {
      log('Failed to fetch linked DN: $e');
    }
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      print('Failed to fetch linked POS Upload: $e');
    }
  }

  Future<void> fetchRelatedPackingSlips(String dnName) async {
    try {
      // Fetch all packing slips linked to this delivery note
      final response = await _provider.getPackingSlips(
        limit: 1000,
        filters: {'delivery_note': dnName},
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        final allSlips = data.map((json) => PackingSlip.fromJson(json)).toList();
        relatedPackingSlips.value = allSlips;
      }
    } catch (e) {
      log('Failed to fetch related packing slips: $e');
    }
  }

  void _updateOriginalState(PackingSlip slip) {
    _originalJson = jsonEncode(slip.toJson());
    isDirty.value = false;
  }

  void _checkForChanges() {
    if (packingSlip.value == null) return;
    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    final currentJson = jsonEncode(packingSlip.value!.toJson());
    isDirty.value = currentJson != _originalJson;
  }

  void toggleInvoiceExpand(String key) => expandedInvoice.value = expandedInvoice.value == key ? '' : key;

  void setFilter(String filter) => itemFilter.value = filter;

  // --- Grouping & Counting Logic ---

  // Groups based on CURRENT Packing Slip (for internal logic)
  Map<String, List<PackingSlipItem>> get groupedItems {
    if (packingSlip.value == null || packingSlip.value!.items.isEmpty) return {};
    return groupBy(packingSlip.value!.items, (PackingSlipItem item) => item.customInvoiceSerialNumber ?? '0');
  }

  // All Serials available in the Delivery Note
  List<String> get _allDnSerials {
    if (linkedDeliveryNote.value == null) return [];
    return linkedDeliveryNote.value!.items
        .map((i) => i.customInvoiceSerialNumber ?? '0')
        .toSet()
        .toList()
      ..sort((a, b) {
        final intA = int.tryParse(a) ?? 9999;
        final intB = int.tryParse(b) ?? 9999;
        return intA.compareTo(intB);
      });
  }

  String getPosItemName(String serial) {
    if (posUpload.value == null) return '';
    final int idx = int.tryParse(serial) ?? 0;
    final item = posUpload.value!.items.firstWhereOrNull((i) => i.idx == idx);
    return item?.itemName ?? '';
  }

  // Get Total Required Qty for a Serial (Target)
  double getTotalDnQtyForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return 0.0;
    return linkedDeliveryNote.value!.items.where((item) => (item.customInvoiceSerialNumber ?? '0') == serial).fold(0.0, (sum, item) => sum + item.qty);
  }

  // Get Total Packed Qty for a Serial (Drafts + Current + Submitted)
  double getGlobalPackedQty(String serial) {
    double total = 0.0;
    final currentSlipName = packingSlip.value?.name;

    // 1. Sum from Related Slips (excluding current stored version)
    for (var slip in relatedPackingSlips) {
      // If the slip in the list is the current one (saved version), skip it
      // because we will add the current memory version below
      if (slip.name == currentSlipName) continue;

      final items = slip.items.where((i) => (i.customInvoiceSerialNumber ?? '0') == serial);
      for (var i in items) total += i.qty;
    }

    // 2. Sum from Current Memory (Active Form)
    final currentItems = packingSlip.value?.items ?? [];
    final activeItems = currentItems.where((i) => (i.customInvoiceSerialNumber ?? '0') == serial);
    for (var i in activeItems) total += i.qty;

    return total;
  }

  // Count Getters
  int get allCount => _allDnSerials.length;

  int get pendingCount => _allDnSerials.where((serial) {
    final required = getTotalDnQtyForSerial(serial);
    final packed = getGlobalPackedQty(serial);
    return packed < required;
  }).length;

  int get completedCount => _allDnSerials.where((serial) {
    final required = getTotalDnQtyForSerial(serial);
    final packed = getGlobalPackedQty(serial);
    return packed >= required;
  }).length;

  // Filtered List of Serials for UI
  List<String> get visibleGroupKeys {
    final serials = _allDnSerials;
    final filter = itemFilter.value;

    if (filter == 'All') return serials;

    return serials.where((serial) {
      final required = getTotalDnQtyForSerial(serial);
      final packed = getGlobalPackedQty(serial);

      if (filter == 'Pending') return packed < required;
      if (filter == 'Completed') return packed >= required;
      return true;
    }).toList();
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    final item = linkedDeliveryNote.value!.items.firstWhereOrNull((element) => element.name == dnDetail);
    return item?.qty;
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    if (linkedDeliveryNote.value == null) {
      GlobalSnackbar.error(message: 'Delivery Note not loaded yet.');
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
      _prepareSheetForAdd(match);
    } else {
      GlobalSnackbar.error(message: 'Item $itemCode not found in Delivery Note or Batch mismatch.');
    }
  }

  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    return linkedDeliveryNote.value!.items.firstWhereOrNull((item) {
      bool codeMatch = item.itemCode == code;
      bool batchMatch = (batch == null) || (item.batchNo == batch);
      return codeMatch && batchMatch;
    });
  }

  void _prepareSheetForAdd(DeliveryNoteItem item) {
    itemFormKey = GlobalKey<FormState>();
    isEditing.value = false;
    currentItemNameKey = null;
    _populateItemDetails(item);

    // Reset Metadata
    bsItemOwner.value = null;
    bsItemCreation.value = null;
    bsItemModified.value = null;
    bsItemModifiedBy.value = null;

    // Logic for Max Qty in Sheet:
    // Remaining = (DN Item Qty) - (Global Packed Qty for THIS SPECIFIC DN Detail line in all other slips) - (Current Slip Qty for this line)

    // Calculate how much has been packed for this specific line item across all slips
    double globalPackedForLine = 0.0;
    final currentSlipName = packingSlip.value?.name;

    // Other slips
    for(var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for(var i in slip.items) {
        if (i.dnDetail == item.name) globalPackedForLine += i.qty;
      }
    }

    // Current slip
    final currentSlipItems = packingSlip.value?.items ?? [];
    for(var i in currentSlipItems) {
      if (i.dnDetail == item.name) globalPackedForLine += i.qty;
    }

    double remaining = item.qty - globalPackedForLine;
    if (remaining < 0) remaining = 0;

    bsMaxQty.value = remaining;

    final qtyStr = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    bsQtyController.text = qtyStr;
    _initialQty = qtyStr;

    validateSheet();

    // Set Sheet Open Flag
    isItemSheetOpen.value = true;

    Get.bottomSheet(
      const PackingSlipItemFormSheet(),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void editItem(PackingSlipItem item) {
    itemFormKey = GlobalKey<FormState>();
    final dnItem = linkedDeliveryNote.value?.items.firstWhereOrNull((d) => d.name == item.dnDetail);
    if (dnItem == null) return;

    isEditing.value = true;
    currentItemNameKey = item.name;

    // Set Metadata
    bsItemOwner.value = item.owner;
    bsItemCreation.value = item.creation;
    bsItemModified.value = item.modified;
    bsItemModifiedBy.value = item.modifiedBy;

    _populateItemDetails(dnItem);

    // Recalculate max qty considering we are editing THIS item
    double globalPackedOthers = 0.0;
    final currentSlipName = packingSlip.value?.name;

    // Other slips
    for(var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for(var i in slip.items) {
        if (i.dnDetail == item.dnDetail) globalPackedOthers += i.qty;
      }
    }

    // Current slip (excluding the one being edited)
    final currentSlipItems = packingSlip.value?.items ?? [];
    for(var i in currentSlipItems) {
      if (i.dnDetail == item.dnDetail && i.name != item.name) globalPackedOthers += i.qty;
    }

    bsMaxQty.value = dnItem.qty - globalPackedOthers;

    final qtyStr = item.qty.toStringAsFixed(0);
    bsQtyController.text = qtyStr;
    _initialQty = qtyStr;

    validateSheet();

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      const PackingSlipItemFormSheet(),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void _populateItemDetails(DeliveryNoteItem item) {
    currentItemDnDetail = item.name;
    currentItemCode = item.itemCode;
    currentItemName = item.itemName;
    currentBatchNo = item.batchNo;
    currentUom = item.uom;
    currentSerial = item.customInvoiceSerialNumber;
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
    if (qtyToAdd <= 0) { Get.back(); return; }

    final currentItems = packingSlip.value?.items.toList() ?? [];
    if (isEditing.value && currentItemNameKey != null) {
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PackingSlipItem(
          name: existing.name,
          dnDetail: existing.dnDetail,
          itemCode: existing.itemCode,
          itemName: existing.itemName,
          qty: qtyToAdd,
          uom: existing.uom,
          batchNo: existing.batchNo,
          netWeight: existing.netWeight,
          weightUom: existing.weightUom,
          customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
          customVariantOf: existing.customVariantOf,
          customCountryOfOrigin: existing.customCountryOfOrigin,
          creation: existing.creation,
          owner: existing.owner,
          modified: existing.modified,
          modifiedBy: existing.modifiedBy,
        );
      }
    } else {
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
          creation: existing.creation,
          owner: existing.owner,
          modified: existing.modified,
          modifiedBy: existing.modifiedBy,
        );
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
          creation: DateTime.now().toString(),
          owner: bsItemOwner.value, // Capture current owner if set, or leave null to be handled by server
          modified: null,
          modifiedBy: null,
        );
        currentItems.add(newItem);
      }
    }
    packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
    Get.back();
    _checkForChanges();
    if (isDirty.value) await savePackingSlip();
  }

  Future<void> deleteCurrentItem() async {
    if (currentItemNameKey == null) return;
    Get.back();

    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Are you sure you want to remove this item from the package?',
      confirmText: 'Remove',
      onConfirm: () async {
        final currentItems = packingSlip.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == currentItemNameKey);
        packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
        _checkForChanges();
        if (isDirty.value) await savePackingSlip();
      },
    );
  }

  Future<void> savePackingSlip() async {
    if (!isDirty.value && mode != 'new') return;
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
          final json = {'item_code': e.itemCode, 'qty': e.qty, 'dn_detail': e.dnDetail, 'custom_invoice_serial_number': e.customInvoiceSerialNumber};
          if (e.name.isNotEmpty) json['name'] = e.name;
          return json;
        }).toList(),
      };
      final response = isNew ? await _apiProvider.createDocument('Packing Slip', data) : await _apiProvider.updateDocument('Packing Slip', docName, data);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = PackingSlip.fromJson(response.data['data']);
        packingSlip.value = saved;
        _updateOriginalState(saved);
        if (isNew) { name = saved.name; mode = 'edit'; GlobalSnackbar.success(message: 'Packing Slip Created: ${saved.name}'); } else { GlobalSnackbar.success(message: 'Packing Slip Saved'); }
      } else { GlobalSnackbar.error(message: 'Failed to save Packing Slip'); }
    } catch (e) { GlobalSnackbar.error(message: 'Save failed: $e'); } finally { isSaving.value = false; }
  }
}