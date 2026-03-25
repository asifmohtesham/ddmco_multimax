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
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/modules/packing_slip/form/controllers/packing_slip_item_form_controller.dart';
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_item_form_sheet.dart'
    show BatchDisplayTile;

class PackingSlipFormController extends GetxController
    with OptimisticLockingMixin {
  final PackingSlipProvider  _provider          = Get.find<PackingSlipProvider>();
  final DeliveryNoteProvider _dnProvider        = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider    _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider          _apiProvider       = Get.find<ApiProvider>();
  final StorageService       _storageService    = Get.find<StorageService>();

  var itemFormKey = GlobalKey<FormState>();
  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading  = true.obs;
  var isSaving   = false.obs;
  var isScanning = false.obs;
  var isDirty    = false.obs;
  // Step-2: isAddingItem needed so child controller can wire isAddingItemFlag.
  var isAddingItem = false.obs;
  String _originalJson = '';

  // bsQtyController kept as a shim until step-6 removes addItemToSlip().
  final bsQtyController = TextEditingController();
  var bsMaxQty  = 0.0.obs;
  // isSheetValid kept until step-6 (still read by old validateSheet() shim).
  var isSheetValid = false.obs;
  String _initialQty = '';

  var packingSlip        = Rx<PackingSlip?>(null);
  var linkedDeliveryNote = Rx<DeliveryNote?>(null);
  var posUpload          = Rx<PosUpload?>(null);

  var relatedPackingSlips = <PackingSlip>[].obs;

  final TextEditingController barcodeController = TextEditingController();

  var expandedInvoice = ''.obs;

  // Step-2: isEditing kept for addItemToSlip() shim.
  var isEditing = false.obs;

  var itemFilter = ''.obs;

  var isItemSheetOpen = false.obs;

  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // Temporary state populated in _populateItemDetails.
  String? currentItemDnDetail;
  String? currentItemCode;
  String? currentItemName;
  String? currentBatchNo;
  String? currentUom;
  String? currentSerial;
  double? currentNetWeight;
  double? currentWeightUom;
  String? currentItemNameKey;
  // Step-2: variant-of for itemSubtext in UniversalItemFormSheet.
  String? currentItemVariantOf;

  // Metadata — kept as shim until step-6 removes addItemToSlip().
  var bsItemOwner      = RxnString();
  var bsItemCreation   = RxnString();
  var bsItemModified   = RxnString();
  var bsItemModifiedBy = RxnString();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    // Step-2: bsQtyController listener kept only for the addItemToSlip() shim.
    // The ever(isSheetValid) auto-submit worker is removed — auto-submit is now
    // wired via child.setupAutoSubmit() in _openItemSheet.
    bsQtyController.addListener(_validateSheetShim);

    if (mode == 'new') {
      _initNewPackingSlip();
    } else {
      fetchPackingSlip();
    }
  }

  /// Shim: keeps isSheetValid in sync so addItemToSlip() guard still works
  /// until step-6 removes both.
  void _validateSheetShim() {
    final text = bsQtyController.text;
    final qty  = double.tryParse(text);
    if (qty == null || qty <= 0)                          { isSheetValid.value = false; return; }
    if (bsMaxQty.value > 0 && qty > bsMaxQty.value)      { isSheetValid.value = false; return; }
    if (isEditing.value && text == _initialQty)           { isSheetValid.value = false; return; }
    isSheetValid.value = true;
  }

  @override
  void onClose() {
    barcodeController.dispose();
    bsQtyController.dispose();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Pop / discard
  // ---------------------------------------------------------------------------

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Document init / fetch
  // ---------------------------------------------------------------------------

  void _initNewPackingSlip() {
    isLoading.value = true;
    final String dnName     = Get.arguments['deliveryNote'] ?? '';
    final String? customPoNo = Get.arguments['customPoNo'];
    final int nextCaseNo    = Get.arguments['nextCaseNo'] ?? 1;
    packingSlip.value = PackingSlip(
      name:         'New Packing Slip',
      deliveryNote: dnName,
      modified:     '',
      creation:     DateTime.now().toString(),
      docstatus:    0,
      status:       'Draft',
      customPoNo:   customPoNo,
      fromCaseNo:   nextCaseNo,
      toCaseNo:     nextCaseNo,
      items:        [],
      customer:     '',
    );
    isDirty.value  = true;
    _originalJson  = '';
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
      GlobalSnackbar.error(message: 'Failed to load data: \${e.toString()}');
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
        if (dn.poNo != null && dn.poNo!.isNotEmpty) fetchPosUpload(dn.poNo!);
        if (packingSlip.value != null &&
            (packingSlip.value!.customer == null ||
                packingSlip.value!.customer!.isEmpty)) {
          packingSlip.value = packingSlip.value!.copyWith(customer: dn.customer);
          if (mode != 'new') _updateOriginalState(packingSlip.value!);
        }
      }
    } catch (e) {
      log('Failed to fetch linked DN: \$e');
    }
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      log('Failed to fetch linked POS Upload: \$e');
    }
  }

  Future<void> fetchRelatedPackingSlips(String dnName) async {
    try {
      final response = await _provider.getPackingSlips(
        limit: 1000,
        filters: {'delivery_note': dnName},
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        relatedPackingSlips.value =
            data.map((json) => PackingSlip.fromJson(json)).toList();
      }
    } catch (e) {
      log('Failed to fetch related packing slips: \$e');
    }
  }

  void _updateOriginalState(PackingSlip slip) {
    _originalJson = jsonEncode(slip.toJson());
    isDirty.value = false;
  }

  void _checkForChanges() {
    if (packingSlip.value == null) return;
    if (mode == 'new') { isDirty.value = true; return; }
    final currentJson = jsonEncode(packingSlip.value!.toJson());
    isDirty.value = currentJson != _originalJson;
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  void toggleInvoiceExpand(String key) =>
      expandedInvoice.value = expandedInvoice.value == key ? '' : key;

  void setFilter(String filter) => itemFilter.value = filter;

  // ---------------------------------------------------------------------------
  // Grouping & counting
  // ---------------------------------------------------------------------------

  Map<String, List<PackingSlipItem>> get groupedItems {
    if (packingSlip.value == null || packingSlip.value!.items.isEmpty) return {};
    return groupBy(packingSlip.value!.items,
        (PackingSlipItem item) => item.customInvoiceSerialNumber ?? '0');
  }

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
    final item =
        posUpload.value!.items.firstWhereOrNull((i) => i.idx == idx);
    return item?.itemName ?? '';
  }

  List<DeliveryNoteItem> getDnItemsForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return [];
    return linkedDeliveryNote.value!.items
        .where((item) => (item.customInvoiceSerialNumber ?? '0') == serial)
        .toList();
  }

  double getTotalDnQtyForSerial(String serial) {
    if (linkedDeliveryNote.value == null) return 0.0;
    return linkedDeliveryNote.value!.items
        .where((item) => (item.customInvoiceSerialNumber ?? '0') == serial)
        .fold(0.0, (sum, item) => sum + item.qty);
  }

  double getPackedQtyForDnItem(String? dnDetail) {
    if (dnDetail == null) return 0.0;
    double total = 0.0;
    final currentSlipName = packingSlip.value?.name;
    for (var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (var i in slip.items) {
        if (i.dnDetail == dnDetail) total += i.qty;
      }
    }
    for (var i in (packingSlip.value?.items ?? [])) {
      if (i.dnDetail == dnDetail) total += i.qty;
    }
    return total;
  }

  PackingSlipItem? getCurrentSlipItem(String? dnDetail) {
    if (dnDetail == null) return null;
    return packingSlip.value?.items
        .firstWhereOrNull((i) => i.dnDetail == dnDetail);
  }

  double getGlobalPackedQty(String serial) {
    double total = 0.0;
    final currentSlipName = packingSlip.value?.name;
    for (var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (var i in slip.items) {
        if ((i.customInvoiceSerialNumber ?? '0') == serial) total += i.qty;
      }
    }
    for (var i in (packingSlip.value?.items ?? [])) {
      if ((i.customInvoiceSerialNumber ?? '0') == serial) total += i.qty;
    }
    return total;
  }

  int get allCount       => _allDnSerials.length;
  int get pendingCount   =>
      _allDnSerials.where((s) => getGlobalPackedQty(s) < getTotalDnQtyForSerial(s)).length;
  int get completedCount =>
      _allDnSerials.where((s) => getGlobalPackedQty(s) >= getTotalDnQtyForSerial(s)).length;

  List<String> get visibleGroupKeys {
    final serials = _allDnSerials;
    final filter  = itemFilter.value;
    if (filter == 'All' || filter.isEmpty) return serials;
    return serials.where((s) {
      final required = getTotalDnQtyForSerial(s);
      final packed   = getGlobalPackedQty(s);
      if (filter == 'Pending')   return packed < required;
      if (filter == 'Completed') return packed >= required;
      return true;
    }).toList();
  }

  double? getRequiredQty(String dnDetail) {
    if (linkedDeliveryNote.value == null) return null;
    return linkedDeliveryNote.value!.items
        .firstWhereOrNull((e) => e.name == dnDetail)
        ?.qty;
  }

  // ---------------------------------------------------------------------------
  // Optimistic-lock reload
  // ---------------------------------------------------------------------------

  @override
  Future<void> reloadDocument() async {
    await fetchPackingSlip();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  Future<void> scanBarcode(String barcode) async {
    if (isItemSheetOpen.value) return;
    if (checkStaleAndBlock()) return;
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
      final ean   = parts.first;
      itemCode    = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo     = parts.join('-');
    } else {
      final ean = barcode;
      itemCode  = ean.length > 7 ? ean.substring(0, 7) : ean;
      batchNo   = null;
    }
    final match = _findItemInDN(itemCode, batchNo);
    isScanning.value = false;
    barcodeController.clear();
    if (match != null) {
      prepareSheetForAdd(match);
    } else {
      GlobalSnackbar.error(
          message: 'Item \$itemCode not found in Delivery Note or Batch mismatch.');
    }
  }

  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    return linkedDeliveryNote.value!.items.firstWhereOrNull((item) {
      final codeMatch  = item.itemCode == code;
      final batchMatch = (batch == null) || (item.batchNo == batch);
      return codeMatch && batchMatch;
    });
  }

  // ---------------------------------------------------------------------------
  // Sheet: shared private opener (Step-2)
  // ---------------------------------------------------------------------------

  /// Opens the item sheet using [UniversalItemFormSheet] inside a
  /// [DraggableScrollableSheet]. Mirrors StockEntryFormController._openItemSheet:
  ///   • async/await lifecycle (no .whenComplete)
  ///   • scrollController wired from DSS builder
  ///   • isSaveEnabled respects docstatus
  ///   • isLoading wired to child.isSheetLoading
  ///   • Get.delete<PackingSlipItemFormController>() after await
  Future<void> _openItemSheet(PackingSlipItemFormController child) async {
    isItemSheetOpen.value = true;
    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.95,
        expand:           false,
        builder: (context, sc) => UniversalItemFormSheet(
          key:              ValueKey(child.editingItemName.value ?? 'new'),
          controller:       child,
          scrollController: sc,
          onSubmit:         addItemToSlip,
          onScan:           null,
          isSaveEnabled:    packingSlip.value?.docstatus == 0,
          itemSubtext:      currentItemVariantOf,
          customFields: [
            if (currentBatchNo != null && currentBatchNo!.isNotEmpty)
              BatchDisplayTile(batchNo: currentBatchNo!),
          ],
        ),
      ),
      isScrollControlled: true,
    );
    // Reliable post-await cleanup.
    isItemSheetOpen.value = false;
    Get.delete<PackingSlipItemFormController>();
  }

  // ---------------------------------------------------------------------------
  // Sheet: add
  // ---------------------------------------------------------------------------

  void prepareSheetForAdd(DeliveryNoteItem item) {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    itemFormKey              = GlobalKey<FormState>();
    isEditing.value          = false;
    currentItemNameKey       = null;
    _populateItemDetails(item);

    bsItemOwner.value      = null;
    bsItemCreation.value   = null;
    bsItemModified.value   = null;
    bsItemModifiedBy.value = null;

    // Compute remaining qty.
    double globalPackedForLine = 0.0;
    final currentSlipName = packingSlip.value?.name;
    for (var slip in relatedPackingSlips) {
      if (slip.name == currentSlipName) continue;
      for (var i in slip.items) {
        if (i.dnDetail == item.name) globalPackedForLine += i.qty;
      }
    }
    for (var i in (packingSlip.value?.items ?? [])) {
      if (i.dnDetail == item.name) globalPackedForLine += i.qty;
    }
    double remaining = item.qty - globalPackedForLine;
    if (remaining < 0) remaining = 0;
    bsMaxQty.value = remaining;

    final qtyStr         = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    bsQtyController.text = qtyStr;
    _initialQty          = qtyStr;
    _validateSheetShim();

    // Create child, initialise, wire auto-submit, open sheet.
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:   this,
      itemCode: item.itemCode,
      itemName: item.itemName ?? '',
    );
    child.setupAutoSubmit(
      enabled:       _storageService.getAutoSubmitEnabled(),
      delaySeconds:  _storageService.getAutoSubmitDelay(),
      isSheetOpen:   isItemSheetOpen,
      isSubmittable: () => packingSlip.value?.docstatus == 0,
      onAutoSubmit:  () async {
        isAddingItem.value = true;
        await Future.delayed(const Duration(milliseconds: 500));
        await addItemToSlip();
        isAddingItem.value = false;
      },
    );
    _openItemSheet(child);
  }

  // ---------------------------------------------------------------------------
  // Sheet: edit
  // ---------------------------------------------------------------------------

  Future<void> editItem(PackingSlipItem item) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    try {
      itemFormKey = GlobalKey<FormState>();
      final dnItem = linkedDeliveryNote.value?.items
          .firstWhereOrNull((d) => d.name == item.dnDetail);
      if (dnItem == null) return;

      isEditing.value    = true;
      currentItemNameKey = item.name;

      bsItemOwner.value      = item.owner;
      bsItemCreation.value   = item.creation;
      bsItemModified.value   = item.modified;
      bsItemModifiedBy.value = item.modifiedBy;

      _populateItemDetails(dnItem);

      // Compute remaining qty excluding this item.
      double globalPackedOthers = 0.0;
      final currentSlipName = packingSlip.value?.name;
      for (var slip in relatedPackingSlips) {
        if (slip.name == currentSlipName) continue;
        for (var i in slip.items) {
          if (i.dnDetail == item.dnDetail) globalPackedOthers += i.qty;
        }
      }
      for (var i in (packingSlip.value?.items ?? [])) {
        if (i.dnDetail == item.dnDetail && i.name != item.name) {
          globalPackedOthers += i.qty;
        }
      }
      bsMaxQty.value = dnItem.qty - globalPackedOthers;

      final qtyStr         = item.qty.toStringAsFixed(0);
      bsQtyController.text = qtyStr;
      _initialQty          = qtyStr;
      _validateSheetShim();

      // Create child, initialise with editingItem, wire auto-submit, open sheet.
      final child = Get.put(PackingSlipItemFormController());
      child.initialise(
        parent:      this,
        itemCode:    dnItem.itemCode,
        itemName:    dnItem.itemName ?? '',
        editingItem: item,
      );
      child.setupAutoSubmit(
        enabled:       _storageService.getAutoSubmitEnabled(),
        delaySeconds:  _storageService.getAutoSubmitDelay(),
        isSheetOpen:   isItemSheetOpen,
        isSubmittable: () => packingSlip.value?.docstatus == 0,
        onAutoSubmit:  () async {
          isAddingItem.value = true;
          await Future.delayed(const Duration(milliseconds: 500));
          await addItemToSlip();
          isAddingItem.value = false;
        },
      );
      _openItemSheet(child);
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  void confirmAndDeleteItem(PackingSlipItem item) {
    if (isItemSheetOpen.value) {
      if (Get.isBottomSheetOpen == true) Get.back();
    }
    GlobalDialog.showConfirmation(
      title:   'Remove Item?',
      message: 'Are you sure you want to remove \${item.itemCode} from this package?',
      onConfirm: () async {
        final items = packingSlip.value?.items.toList() ?? [];
        items.removeWhere((i) => i.name == item.name);
        packingSlip.value = packingSlip.value?.copyWith(items: items);
        _checkForChanges();
        GlobalSnackbar.success(message: 'Item removed');
        if (isDirty.value) await savePackingSlip();
      },
    );
  }

  void _populateItemDetails(DeliveryNoteItem item) {
    currentItemDnDetail    = item.name;
    currentItemCode        = item.itemCode;
    currentItemName        = item.itemName;
    currentBatchNo         = item.batchNo;
    currentUom             = item.uom;
    currentSerial          = item.customInvoiceSerialNumber;
    currentNetWeight       = 0.0;
    currentWeightUom       = 0.0;
    // Step-2: expose variant-of for itemSubtext.
    currentItemVariantOf   = (item as dynamic).customVariantOf as String?;
  }

  void adjustQty(double delta) {
    double current = double.tryParse(bsQtyController.text) ?? 0;
    double newVal  = current + delta;
    if (newVal < 0) newVal = 0;
    if (newVal > bsMaxQty.value) newVal = bsMaxQty.value;
    bsQtyController.text = newVal.toStringAsFixed(0);
  }

  // ---------------------------------------------------------------------------
  // Commit item (shim — kept until step-6 removes it)
  // ---------------------------------------------------------------------------

  Future<void> addItemToSlip() async {
    final double qtyToAdd = double.tryParse(bsQtyController.text) ?? 0;
    if (qtyToAdd <= 0) { Get.back(); return; }

    final currentItems = packingSlip.value?.items.toList() ?? [];
    if (isEditing.value && currentItemNameKey != null) {
      final index = currentItems.indexWhere((i) => i.name == currentItemNameKey);
      if (index != -1) {
        final existing = currentItems[index];
        currentItems[index] = PackingSlipItem(
          name:       existing.name,
          dnDetail:   existing.dnDetail,
          itemCode:   existing.itemCode,
          itemName:   existing.itemName,
          qty:        qtyToAdd,
          uom:        existing.uom,
          batchNo:    existing.batchNo,
          netWeight:  existing.netWeight,
          weightUom:  existing.weightUom,
          customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
          customVariantOf:           existing.customVariantOf,
          customCountryOfOrigin:     existing.customCountryOfOrigin,
          creation:   existing.creation,
          owner:      existing.owner,
          modified:   existing.modified,
          modifiedBy: existing.modifiedBy,
        );
      }
    } else {
      final existingIndex =
          currentItems.indexWhere((i) => i.dnDetail == currentItemDnDetail);
      if (existingIndex != -1) {
        final existing = currentItems[existingIndex];
        currentItems[existingIndex] = PackingSlipItem(
          name:       existing.name,
          dnDetail:   existing.dnDetail,
          itemCode:   existing.itemCode,
          itemName:   existing.itemName,
          qty:        existing.qty + qtyToAdd,
          uom:        existing.uom,
          batchNo:    existing.batchNo,
          netWeight:  existing.netWeight,
          weightUom:  existing.weightUom,
          customInvoiceSerialNumber: existing.customInvoiceSerialNumber,
          customVariantOf:           existing.customVariantOf,
          customCountryOfOrigin:     existing.customCountryOfOrigin,
          creation:   existing.creation,
          owner:      existing.owner,
          modified:   existing.modified,
          modifiedBy: existing.modifiedBy,
        );
      } else {
        currentItems.add(PackingSlipItem(
          name:        '',
          dnDetail:    currentItemDnDetail!,
          itemCode:    currentItemCode!,
          itemName:    currentItemName ?? '',
          qty:         qtyToAdd,
          uom:         currentUom ?? '',
          batchNo:     currentBatchNo ?? '',
          netWeight:   0.0,
          weightUom:   0.0,
          customInvoiceSerialNumber: currentSerial,
          customVariantOf:           null,
          customCountryOfOrigin:     null,
          creation:    DateTime.now().toString(),
          owner:       bsItemOwner.value,
          modified:    null,
          modifiedBy:  null,
        ));
      }
    }
    packingSlip.value = packingSlip.value?.copyWith(items: currentItems);
    Get.back();
    _checkForChanges();
    if (isDirty.value) await savePackingSlip();
  }

  // ---------------------------------------------------------------------------
  // deleteCurrentItem — called by child.deleteCurrentItem()
  // ---------------------------------------------------------------------------

  Future<void> deleteCurrentItem() async {
    if (currentItemNameKey == null) return;
    Get.back();
    GlobalDialog.showConfirmation(
      title:       'Remove Item?',
      message:     'Are you sure you want to remove this item from the package?',
      confirmText: 'Remove',
      onConfirm: () async {
        final items = packingSlip.value?.items.toList() ?? [];
        items.removeWhere((i) => i.name == currentItemNameKey);
        packingSlip.value = packingSlip.value?.copyWith(items: items);
        _checkForChanges();
        if (isDirty.value) await savePackingSlip();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> savePackingSlip() async {
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    try {
      final docName = packingSlip.value?.name ?? '';
      final isNew   = docName == 'New Packing Slip';
      final Map<String, dynamic> data = {
        'delivery_note': packingSlip.value!.deliveryNote,
        'from_case_no':  packingSlip.value!.fromCaseNo,
        'to_case_no':    packingSlip.value!.toCaseNo,
        'custom_po_no':  packingSlip.value!.customPoNo,
        'modified':      packingSlip.value?.modified,
        'items': packingSlip.value!.items.map((e) {
          final json = <String, dynamic>{
            'item_code':                    e.itemCode,
            'qty':                          e.qty,
            'dn_detail':                    e.dnDetail,
            'custom_invoice_serial_number': e.customInvoiceSerialNumber,
          };
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
        _updateOriginalState(saved);
        if (isNew) {
          name = saved.name;
          mode = 'edit';
          GlobalSnackbar.success(message: 'Packing Slip Created: \${saved.name}');
        } else {
          GlobalSnackbar.success(message: 'Packing Slip Saved');
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to save Packing Slip');
      }
    } catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: 'Save failed: \$e');
    } finally {
      isSaving.value = false;
    }
  }
}
