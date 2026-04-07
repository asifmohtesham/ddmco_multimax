import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';

import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';

import 'delivery_note_item_form_controller.dart';

class DeliveryNoteFormController extends GetxController
    with OptimisticLockingMixin {
  final DeliveryNoteProvider _provider         = Get.find<DeliveryNoteProvider>();
  final ApiProvider          _apiProvider      = Get.find<ApiProvider>();
  final ScanService          _scanService      = Get.find<ScanService>();
  final StorageService       _storageService   = Get.find<StorageService>();
  final DataWedgeService     _dataWedgeService = Get.find<DataWedgeService>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  // ── Document-level state ──────────────────────────────────────────────
  var isLoading          = true.obs;
  var isSaving           = false.obs;
  var isDirty            = false.obs;
  var isScanning         = false.obs;
  var isAddingItem       = false.obs;
  var isLoadingItemEdit  = false.obs;
  var isItemSheetOpen    = false.obs;

  var loadingForItemName   = RxnString();
  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial   = ''.obs;

  // ── Save result state machine ─────────────────────────────────────────
  var saveResult     = SaveResult.idle.obs;
  Timer? _saveResultTimer;

  void _setSaveResult(SaveResult result) {
    _saveResultTimer?.cancel();
    saveResult.value = result;
    _saveResultTimer = Timer(const Duration(seconds: 2), () {
      saveResult.value = SaveResult.idle;
    });
  }

  var deliveryNote = Rx<DeliveryNote?>(null);

  // ── Header form controllers ───────────────────────────────────────────
  final customerController    = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  final barcodeController     = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // ── Warehouse ─────────────────────────────────────────────────────────
  var setWarehouse         = RxnString();
  var bsItemWarehouse      = RxnString();
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── POS Upload ────────────────────────────────────────────────────────
  var posUpload = Rx<PosUpload?>(null);

  // ── EAN context ───────────────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Persistent scan worker ────────────────────────────────────────────
  Worker? _scanWorker;

  bool get isEditable => (deliveryNote.value?.docstatus ?? 1) == 0;

  List<DeliveryNoteItem> get items =>
      deliveryNote.value?.items ?? const [];

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    customerController.addListener(_markDirty);
    postingDateController.addListener(_markDirty);
    postingTimeController.addListener(_markDirty);
    ever(setWarehouse, (_) => _markDirty());

    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[DN:onInit] _scanWorker registered', name: 'DN');

    if (mode == 'new') {
      _initNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) isDirty.value = true;
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    log('[DN:onClose] _scanWorker disposed', name: 'DN');
    customerController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDeliveryNote();
    isStale.value    = false;
    isScanning.value = false;
    AppNotification.success('Document reloaded successfully');
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Raw scan entry point ──────────────────────────────────────────────
  void _onRawScan(String code) {
    log('[DN:_onRawScan] code="$code" route=${Get.currentRoute}', name: 'DN');
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.DELIVERY_NOTE_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ── Data fetching ─────────────────────────────────────────────────────
  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
          'Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      log('[DN:fetchWarehouses] error: $e', name: 'DN');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  Future<void> _initNewDeliveryNote() async {
    isLoading.value = true;
    final now      = DateTime.now();
    final customer = Get.arguments['customer'] ?? '';
    final posName  = Get.arguments['posUpload'] as String?;

    deliveryNote.value = DeliveryNote(
      name:        'new',
      customer:    customer,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      docstatus:   0,
      items:       [],
    );

    customerController.text    = customer;
    postingDateController.text = DateFormat('yyyy-MM-dd').format(now);
    postingTimeController.text = DateFormat('HH:mm:ss').format(now);

    if (posName != null && posName.isNotEmpty) {
      await _loadPosUpload(posName);
    }

    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final dn = DeliveryNote.fromJson(
            response.data['data'] as Map<String, dynamic>);
        deliveryNote.value = dn;

        customerController.text    = dn.customer ?? '';
        postingDateController.text = dn.postingDate ?? '';
        postingTimeController.text = dn.postingTime ?? '';
        setWarehouse.value         = dn.setWarehouse;

        captureVersion(dn.modified);

        final posName = dn.customPosUpload;
        if (posName != null && posName.isNotEmpty) {
          await _loadPosUpload(posName);
        }
      }
    } catch (e) {
      log('[DN:fetchDeliveryNote] error: $e', name: 'DN');
      GlobalSnackbar.error(message: 'Failed to load Delivery Note');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadPosUpload(String posName) async {
    try {
      final response = await _apiProvider.getDocument('POS Upload', posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value =
            PosUpload.fromJson(response.data['data'] as Map<String, dynamic>);
        log('[DN:_loadPosUpload] loaded ${posUpload.value?.items.length} items',
            name: 'DN');
      }
    } catch (e) {
      log('[DN:_loadPosUpload] error: $e', name: 'DN');
    }
  }

  // ── POS qty-cap helper ────────────────────────────────────────────────
  double posQtyCapForSerial(String serial) {
    final upload = posUpload.value;
    if (upload == null) return double.infinity;
    final idx = int.tryParse(serial);
    if (idx == null) return double.infinity;
    final item = upload.items.firstWhereOrNull((i) => i.idx == idx);
    if (item == null) return double.infinity;
    return item.quantity.toDouble();
  }

  /// Sum of qty already scanned across all DN items for a given serial (idx).
  /// Pass [excludeItemName] to omit the row currently being edited
  /// (prevents double-counting in edit mode).
  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return items
        .where((i) =>
            i.customInvoiceSerialNumber == serial &&
            i.name != excludeItemName)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  // ── Warehouse setter ──────────────────────────────────────────────────
  void setWarehouseValue(String? value) {
    setWarehouse.value = value;
  }

  // ── OptimisticLockingMixin ────────────────────────────────────────────
  @override
  String? get currentVersion => deliveryNote.value?.modified;

  bool _validateHeaderBeforeScan() {
    if (!isEditable) {
      GlobalSnackbar.error(message: 'Document is submitted. Cannot scan.');
      return false;
    }
    if ((setWarehouse.value ?? '').isEmpty) {
      GlobalSnackbar.error(message: 'Set warehouse before scanning');
      return false;
    }
    return true;
  }

  // ── Sheet-scan routing ────────────────────────────────────────────────
  //
  // Commit 3 (fix #17): upgrade _handleSheetScan to processScan-based routing
  // matching PurchaseReceiptFormController behaviour.
  //
  // Sequence:
  //   ScanType.rack   → child.applyRackScan(rackId)
  //   ScanType.batch  → child.batchController + validateBatch()
  //   else            → GlobalSnackbar.error (unknown barcode)
  Future<void> _handleSheetScan(String barcode) async {
    barcodeController.clear();
    if (!Get.isRegistered<DeliveryNoteItemFormController>()) {
      log('[DN:_handleSheetScan] child not registered — scan dropped', name: 'DN');
      return;
    }

    final child = Get.find<DeliveryNoteItemFormController>();
    final contextEan = child.currentScannedEan.isNotEmpty
        ? child.currentScannedEan
        : child.itemCode.value;

    final result =
        await _scanService.processScan(barcode, contextItemCode: contextEan);

    if (result.type == ScanType.rack && result.rackId != null) {
      child.applyRackScan(result.rackId!);
    } else if (result.batchNo != null) {
      child.batchController.text = result.batchNo!;
      child.validateBatch(result.batchNo!);
    } else {
      GlobalSnackbar.error(message: result.message ?? 'Invalid input for this field');
    }
  }

  Future<void> scanBarcode(String barcode) async {
    // Commit 3 (fix #17): await _handleSheetScan since it is now async.
    if (isItemSheetOpen.value && Get.isBottomSheetOpen == true) {
      await _handleSheetScan(barcode);
      return;
    }
    if (!_validateHeaderBeforeScan()) return;
    if (isScanning.value || isAddingItem.value) return;
    if (barcode.isEmpty) return;

    final cleanBarcode = barcode.trim();
    isScanning.value = true;

    try {
      final result = await _scanService.processScan(cleanBarcode);

      switch (result.type) {
        case ScanType.item:
          currentScannedEan = result.itemCode ?? '';
          await _handleScanResult(result);
          break;
        case ScanType.batch:
          currentScannedEan = '';
          await _handleScanResult(result);
          break;
        case ScanType.multiple:
          isScanning.value = false;
          await _showMultipleMatchSheet(result.candidates ?? []);
          break;
        case ScanType.rack:
        case ScanType.variant_of:
        case ScanType.unknown:
        case ScanType.error:
          GlobalSnackbar.error(
            message: 'Item not found for barcode: $cleanBarcode',
          );
          break;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  Future<void> _handleScanResult(ScanResult result) async {
    isScanning.value = false;
    await _openItemSheet(
      itemCode:  result.itemCode!,
      itemName:  result.itemData?.itemName ?? result.itemCode!,
      batchNo:   result.batchNo,
      variantOf: result.itemData?.variantOf,
    );
  }

  Future<void> _showMultipleMatchSheet(List<Item> candidates) async {
    await Get.bottomSheet(
      _MultipleMatchSheet(candidates: candidates, parent: this),
      isScrollControlled: true,
    );
  }

  // ── Item CRUD ─────────────────────────────────────────────────────────
  void addItem(DeliveryNoteItem newItem) {
    deliveryNote.value?.items.add(newItem);
    deliveryNote.refresh();
    _checkForChanges();
    recentlyAddedItemCode.value = newItem.itemCode;
    recentlyAddedSerial.value   = newItem.customInvoiceSerialNumber ?? '';
    Future.delayed(const Duration(seconds: 2), () {
      if (recentlyAddedItemCode.value == newItem.itemCode) {
        recentlyAddedItemCode.value = '';
      }
    });
    _scrollToItem(newItem.name ?? newItem.itemCode);
    if (mode == 'edit') saveDeliveryNote();
  }

  void updateItem(DeliveryNoteItem updatedItem) {
    final items = deliveryNote.value?.items ?? [];
    final idx   = items.indexWhere((i) => i.name == updatedItem.name);
    if (idx != -1) {
      items[idx] = updatedItem;
      deliveryNote.refresh();
      _checkForChanges();
    }
    if (mode == 'edit') saveDeliveryNote();
  }

  void addItemLocally(
    String code,
    String itemName,
    String uom, {
    String? batchNo,
    String? variantOf,
  }) {
    final item = DeliveryNoteItem(
      itemCode:        code,
      itemName:        itemName,
      uom:             uom,
      qty:             1.0,
      rate:            0.0,
      batchNo:         batchNo,
      customVariantOf: variantOf,
    );
    deliveryNote.value?.items.add(item);
    deliveryNote.refresh();
    _checkForChanges();
  }

  void updateItemLocally(int index, DeliveryNoteItem updatedItem) {
    final items = deliveryNote.value?.items ?? [];
    if (index >= 0 && index < items.length) {
      items[index] = updatedItem;
      deliveryNote.refresh();
      _checkForChanges();
    }
  }

  void removeItem(int index) {
    deliveryNote.value?.items.removeAt(index);
    deliveryNote.refresh();
    _checkForChanges();
    if (mode == 'edit') saveDeliveryNote();
  }

  void _checkForChanges() => _markDirty();

  // ── Item sheet ────────────────────────────────────────────────────────
  Future<void> openItemSheetForCode(
    String itemCode,
    String itemName, {
    String? batchNo,
    String? variantOf,
  }) async {
    await _openItemSheet(
      itemCode:  itemCode,
      itemName:  itemName,
      batchNo:   batchNo,
      variantOf: variantOf,
    );
  }

  Future<void> editItem(DeliveryNoteItem item) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    try {
      final child = Get.put(DeliveryNoteItemFormController());

      child.initialise(
        parent:      this,
        code:        item.itemCode,
        name:        item.itemName ?? item.itemCode,
        variantOf:   item.customVariantOf,
        editingItem: item,
      );

      child.setupAutoSubmit(
        onValid: () async {
          isAddingItem.value = true;
          final ok = await child.submitWithFeedback();
          isAddingItem.value = false;
          if (ok && Get.isBottomSheetOpen == true) Get.back();
        },
      );

      const rackPickerTag = 'dn_rack_picker';

      isItemSheetOpen.value = true;
      try {
        await Get.bottomSheet(
          UniversalItemFormSheet(
            controller:       child,
            scrollController: child.sheetScrollController,
            customFields: [
              SharedInvoiceSerialNumberField(c: child),
              SharedBatchField(
                c:               child,
                accentColor:     Colors.blueGrey,
                editMode:        true,
                onPickerTap:     child.openBatchPicker,
                balanceOverride: () => child.batchBalance.value,
              ),
              SharedRackField(
                c:               child,
                accentColor:     Colors.blueGrey,
                editMode:        true,
                balanceOverride: () => child.rackBalance.value,
                onPickerTap: () async {
                  HapticFeedback.lightImpact();

                  final picker = Get.put(
                    RackPickerController(),
                    tag: rackPickerTag,
                  );

                  picker.load(
                    itemCode:     child.itemCode.value,
                    batchNo:      child.batchController.text,
                    warehouse:    child.resolvedWarehouse ?? '',
                    requestedQty: double.tryParse(child.qtyController.text) ?? 0.0,
                    currentRack:  child.rackController.text,
                    fallbackMap:  Map<String, double>.from(child.rackStockMap),
                  );

                  await Get.bottomSheet<void>(
                    RackPickerSheet(
                      pickerTag:  rackPickerTag,
                      onSelected: (rackId) => child.applyRackScan(rackId),
                    ),
                    isScrollControlled: true,
                  );

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (Get.isRegistered<RackPickerController>(
                        tag: rackPickerTag)) {
                      Get.delete<RackPickerController>(tag: rackPickerTag);
                    }
                  });
                },
              ),
            ],
            onSubmit: () async {
              final ok = await child.submitWithFeedback();
              if (ok) Get.back();
            },
          ),
          isScrollControlled: true,
          enableDrag:         false,
          isDismissible:      false,
          backgroundColor:    Colors.transparent,
        );
      } finally {
        isItemSheetOpen.value = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          child.disposeControllers();
          Get.delete<DeliveryNoteItemFormController>(force: true);
          log('[DN:editItem] post-frame teardown complete', name: 'DN');
        });
      }
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }
  }

  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String? batchNo,
    String? variantOf,
    DeliveryNoteItem? editingItem,
  }) async {
    if (isItemSheetOpen.value || Get.isBottomSheetOpen == true) return;

    final child = Get.put(DeliveryNoteItemFormController());

    child.initialise(
      parent:      this,
      code:        itemCode,
      name:        itemName,
      batchNo:     batchNo,
      variantOf:   variantOf,
      editingItem: editingItem,
    );

    child.setupAutoSubmit(
      onValid: () async {
        isAddingItem.value = true;
        final ok = await child.submitWithFeedback();
        isAddingItem.value = false;
        if (ok && Get.isBottomSheetOpen == true) Get.back();
      },
    );

    const rackPickerTag = 'dn_rack_picker';

    isItemSheetOpen.value = true;
    try {
      await Get.bottomSheet(
        UniversalItemFormSheet(
          controller:       child,
          scrollController: child.sheetScrollController,
          customFields: [
            // Commit 4: migrated from SharedSerialField to
            // SharedInvoiceSerialNumberField (delegate-driven, zero coupling).
            SharedInvoiceSerialNumberField(c: child),
            SharedBatchField(
              c:               child,
              accentColor:     Colors.blueGrey,
              editMode:        true,
              onPickerTap:     child.openBatchPicker,
              balanceOverride: () => child.batchBalance.value,
            ),
            SharedRackField(
              c:               child,
              accentColor:     Colors.blueGrey,
              editMode:        true,
              balanceOverride: () => child.rackBalance.value,
              onPickerTap: () async {
                HapticFeedback.lightImpact();

                final picker = Get.put(
                  RackPickerController(),
                  tag: rackPickerTag,
                );

                picker.load(
                  itemCode:     child.itemCode.value,
                  batchNo:      child.batchController.text,
                  warehouse:    child.resolvedWarehouse ?? '',
                  requestedQty: double.tryParse(child.qtyController.text) ?? 0.0,
                  currentRack:  child.rackController.text,
                  fallbackMap:  Map<String, double>.from(child.rackStockMap),
                );

                await Get.bottomSheet<void>(
                  RackPickerSheet(
                    pickerTag:  rackPickerTag,
                    onSelected: (rackId) => child.applyRackScan(rackId),
                  ),
                  isScrollControlled: true,
                );

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Get.isRegistered<RackPickerController>(
                      tag: rackPickerTag)) {
                    Get.delete<RackPickerController>(tag: rackPickerTag);
                  }
                });
              },
            ),
          ],
          onSubmit: () async {
            final ok = await child.submitWithFeedback();
            if (ok) Get.back();
          },
        ),
        isScrollControlled: true,
        enableDrag:         false,
        isDismissible:      false,
        backgroundColor:    Colors.transparent,
      );
    } finally {
      isItemSheetOpen.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        child.disposeControllers();
        Get.delete<DeliveryNoteItemFormController>(force: true);
        log('[DN:_openItemSheet] post-frame teardown complete', name: 'DN');
      });
    }
  }

  void _handleCustomerNotFound(String customer) {
    GlobalSnackbar.error(message: 'Customer "$customer" not found');
  }

  // ── Item-key helpers ──────────────────────────────────────────────────
  void ensureItemKey(DeliveryNoteItem item) {
    final key = item.name ?? item.itemCode;
    itemKeys[key] ??= GlobalKey();
  }

  void _scrollToItem(String key) {
    final gk = itemKeys[key];
    if (gk == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = gk.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      }
    });
  }

  // ── Save / submit ─────────────────────────────────────────────────────
  Future<void> saveDeliveryNote() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;
    isSaving.value = true;
    _setSaveResult(SaveResult.idle);
    try {
      final dn = deliveryNote.value;
      if (dn == null) return;

      dn.customer    = customerController.text.trim();
      dn.postingDate = postingDateController.text.trim();
      dn.postingTime = postingTimeController.text.trim();
      dn.setWarehouse = setWarehouse.value;

      Response response;
      if (mode == 'new' || dn.name == 'new') {
        response = await _provider.createDeliveryNote(dn.toJson());
      } else {
        response = await _provider.updateDeliveryNote(dn.name, dn.toJson());
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final saved = DeliveryNote.fromJson(
            response.data['data'] as Map<String, dynamic>);
        deliveryNote.value = saved;
        captureVersion(saved.modified);
        isDirty.value = false;
        mode = 'edit';
        _setSaveResult(SaveResult.success);
        log('[DN:saveDeliveryNote] saved ${saved.name}', name: 'DN');
      } else {
        _setSaveResult(SaveResult.error);
        GlobalSnackbar.error(message: 'Save failed (${response.statusCode})');
      }
    } catch (e) {
      _setSaveResult(SaveResult.error);
      GlobalSnackbar.error(message: 'Save error: $e');
      log('[DN:saveDeliveryNote] error: $e', name: 'DN');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> submitDeliveryNote() async {
    if (checkStaleAndBlock()) return;
    GlobalDialog.showConfirmation(
      title:   'Submit Delivery Note?',
      message: 'This action cannot be undone.',
      onConfirm: () async {
        isSaving.value = true;
        try {
          await saveDeliveryNote();
          final response = await _provider.submitDeliveryNote(
              deliveryNote.value!.name);
          if (response.statusCode == 200) {
            deliveryNote.value?.docstatus = 1;
            deliveryNote.refresh();
            isDirty.value = false;
            GlobalSnackbar.success(message: 'Delivery Note submitted');
          } else {
            GlobalSnackbar.error(message: 'Submit failed');
          }
        } catch (e) {
          GlobalSnackbar.error(message: 'Submit error: $e');
        } finally {
          isSaving.value = false;
        }
      },
    );
  }
}

// ── Private widget ────────────────────────────────────────────────────────────
class _MultipleMatchSheet extends StatelessWidget {
  final List<Item> candidates;
  final DeliveryNoteFormController parent;

  const _MultipleMatchSheet({
    required this.candidates,
    required this.parent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Multiple Items Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...candidates.map((item) => ListTile(
                title: Text(item.itemName ?? item.name),
                subtitle: Text(item.name),
                onTap: () {
                  Get.back();
                  parent.openItemSheetForCode(
                    item.name,
                    item.itemName ?? item.name,
                  );
                },
              )),
        ],
      ),
    );
  }
}
