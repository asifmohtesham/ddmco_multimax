import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_form_sheet.dart';

class PackingSlipFormController extends GetxController {
  final PackingSlipProvider _provider = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider = Get.find<DeliveryNoteProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  var itemFormKey = GlobalKey<FormState>();
  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isScanning = false.obs;

  // Dirty Check State (Document Level)
  var isDirty = false.obs;
  String _originalJson = '';

  // Sheet Validation State (Item Level)
  var isSheetValid = false.obs;
  String _initialQty = '';

  var packingSlip = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);

  final TextEditingController barcodeController = TextEditingController();

  // Grouping State
  var expandedInvoice = ''.obs;

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  var bsMaxQty = 0.0.obs;
  var isEditing = false.obs;

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

  @override
  void onInit() {
    super.onInit();

    // Listen for Sheet Changes
    bsQtyController.addListener(validateSheet);

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

  // --- Sheet Validation Logic ---
  void validateSheet() {
    final text = bsQtyController.text;
    final qty = double.tryParse(text);

    // 1. Basic Validity
    if (qty == null || qty <= 0) {
      isSheetValid.value = false;
      return;
    }

    // 2. Max Constraint
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value) {
      isSheetValid.value = false;
      return;
    }

    // 3. Dirty Check (Only strictly enforced for Editing)
    // For Adding, simply having valid input is enough, even if it matches the default suggestion.
    if (isEditing.value) {
      if (text == _initialQty) {
        isSheetValid.value = false;
        return;
      }
    }

    isSheetValid.value = true;
  }

  // ... (Init and Fetch methods unchanged) ...
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
    if (dnName.isNotEmpty) fetchLinkedDeliveryNote(dnName);
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
        if (slip.deliveryNote.isNotEmpty) await fetchLinkedDeliveryNote(slip.deliveryNote);
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
        if (packingSlip.value != null && (packingSlip.value!.customer == null || packingSlip.value!.customer!.isEmpty)) {
          packingSlip.value = packingSlip.value!.copyWith(customer: dn.customer);
          if (mode != 'new') _checkForChanges();
        }
      }
    } catch (e) {
      log('Failed to fetch linked DN: $e');
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

  // ... (Grouping logic unchanged) ...
  void toggleInvoiceExpand(String key) => expandedInvoice.value = expandedInvoice.value == key ? '' : key;

  Map<String, List<PackingSlipItem>> get groupedItems {
    if (packingSlip.value == null || packingSlip.value!.items.isEmpty) return {};
    return groupBy(packingSlip.value!.items, (PackingSlipItem item) => item.customInvoiceSerialNumber ?? '0');
  }

  double getTotalDnQtyForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return 0.0;
    return linkedDeliveryNote.value!.items.where((item) => (item.customInvoiceSerialNumber ?? '0') == serial).fold(0.0, (sum, item) => sum + item.qty);
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    final item = linkedDeliveryNote.value!.items.firstWhereOrNull((element) => element.name == dnDetail);
    return item?.qty;
  }

  // ... (Scan Logic unchanged) ...
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

  // --- Sheet Setup with Dirty Tracking ---

  void _prepareSheetForAdd(DeliveryNoteItem item) {
    itemFormKey = GlobalKey<FormState>();
    isEditing.value = false;
    currentItemNameKey = null;
    _populateItemDetails(item);

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

    // Set Initial values for Dirty Check
    final qtyStr = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    bsQtyController.text = qtyStr;
    _initialQty = qtyStr;

    validateSheet(); // Initial check

    Get.bottomSheet(
      const PackingSlipItemFormSheet(),
      isScrollControlled: true,
    );
  }

  void editItem(PackingSlipItem item) {
    itemFormKey = GlobalKey<FormState>();
    final dnItem = linkedDeliveryNote.value?.items.firstWhereOrNull((d) => d.name == item.dnDetail);
    if (dnItem == null) return;

    isEditing.value = true;
    currentItemNameKey = item.name;
    _populateItemDetails(dnItem);

    double existingPackedOthers = 0;
    for (var i in packingSlip.value!.items) {
      if (i.dnDetail == item.dnDetail && i.name != item.name) {
        existingPackedOthers += i.qty;
      }
    }
    bsMaxQty.value = dnItem.qty - existingPackedOthers;

    // Set Initial values for Dirty Check
    final qtyStr = item.qty.toStringAsFixed(0);
    bsQtyController.text = qtyStr;
    _initialQty = qtyStr;

    validateSheet(); // Initial check

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
    currentNetWeight = 0.0;
    currentWeightUom = 0.0;
  }

  void adjustQty(double delta) {
    double current = double.tryParse(bsQtyController.text) ?? 0;
    double newVal = current + delta;
    if (newVal < 0) newVal = 0;
    if (newVal > bsMaxQty.value) newVal = bsMaxQty.value;
    bsQtyController.text = newVal.toStringAsFixed(0);
    // Listener calls validateSheet automatically
  }

  // ... (Add/Delete/Save methods unchanged) ...
  Future<void> addItemToSlip() async {
    final double qtyToAdd = double.tryParse(bsQtyController.text) ?? 0;
    if (qtyToAdd <= 0) { Get.back(); return; }

    final currentItems = packingSlip.value?.items.toList() ?? [];
    if (isEditing.value && currentItemNameKey != null) {
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PackingSlipItem(name: existing.name, dnDetail: existing.dnDetail, itemCode: existing.itemCode, itemName: existing.itemName, qty: qtyToAdd, uom: existing.uom, batchNo: existing.batchNo, netWeight: existing.netWeight, weightUom: existing.weightUom, customInvoiceSerialNumber: existing.customInvoiceSerialNumber, customVariantOf: existing.customVariantOf, customCountryOfOrigin: existing.customCountryOfOrigin, creation: existing.creation);
      }
    } else {
      final existingIndex = currentItems.indexWhere((i) => i.dnDetail == currentItemDnDetail);
      if (existingIndex != -1) {
        final existing = currentItems[existingIndex];
        currentItems[existingIndex] = PackingSlipItem(name: existing.name, dnDetail: existing.dnDetail, itemCode: existing.itemCode, itemName: existing.itemName, qty: existing.qty + qtyToAdd, uom: existing.uom, batchNo: existing.batchNo, netWeight: existing.netWeight, weightUom: existing.weightUom, customInvoiceSerialNumber: existing.customInvoiceSerialNumber, customVariantOf: existing.customVariantOf, customCountryOfOrigin: existing.customCountryOfOrigin, creation: existing.creation);
      } else {
        final newItem = PackingSlipItem(name: '', dnDetail: currentItemDnDetail!, itemCode: currentItemCode!, itemName: currentItemName ?? '', qty: qtyToAdd, uom: currentUom ?? '', batchNo: currentBatchNo ?? '', netWeight: 0.0, weightUom: 0.0, customInvoiceSerialNumber: currentSerial, customVariantOf: null, customCountryOfOrigin: null, creation: DateTime.now().toString());
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
    Get.dialog(AlertDialog(title: const Text('Remove Item'), content: const Text('Remove from package?'), actions: [
      TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
      ElevatedButton(onPressed: () async {
        Get.back();
        final currentItems = packingSlip.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == currentItemNameKey);
        packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
        _checkForChanges();
        if (isDirty.value) await savePackingSlip();
      }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Remove', style: TextStyle(color: Colors.white))),
    ]));
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