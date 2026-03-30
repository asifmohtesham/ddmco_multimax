import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/controller_feedback_mixin.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';

// Child sheet controller
import 'delivery_note_item_form_controller.dart';

// (delivery_note_item_form_sheet.dart is now a stub re-export)

class DeliveryNoteFormController extends GetxController
    with OptimisticLockingMixin, ControllerFeedbackMixin {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final StorageService _storageService = Get.find<StorageService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  final String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg  = Get.arguments['posUploadName'];

  // ── Document-level state ──────────────────────────────────────────────
  var isLoading    = true.obs;
  var isScanning   = false.obs;
  var isAddingItem = false.obs;
  var isSaving     = false.obs;
  var isDirty      = false.obs;
  String _originalJson = '';

  // ── Save result state machine ────────────────────────────────────────────
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
  var posUpload    = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice  = ''.obs;
  var itemFilter       = 'All'.obs;

  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial   = ''.obs;
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // ── Sheet-open + item-edit loading flags ────────────────────────────────────────
  var isItemSheetOpen    = false.obs;
  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // ── Warehouse ─────────────────────────────────────────────────────────────
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse         = RxnString();

  // ── Item warehouse (derived from rack) ───────────────────────────────────────────
  var bsItemWarehouse = RxnString();

  // ── Customer-level error ─────────────────────────────────────────────────────
  var customerError = RxnString();

  // ── EAN scan context ───────────────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Persistent scan worker ───────────────────────────────────────────────────
  Worker? _scanWorker;

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    ever(setWarehouse, (_) => _checkForChanges());
    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[DN:onInit] _scanWorker registered on DataWedgeService.scannedCode',
        name: 'DN');

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _saveResultTimer?.cancel();
    disposeFeedback();
    log('[DN:onClose] _scanWorker disposed', name: 'DN');
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ── Raw scan entry point ─────────────────────────────────────────────────
  void _onRawScan(String code) {
    if (code.isEmpty) {
      return;
    }
    if (Get.currentRoute != AppRoutes.DELIVERY_NOTE_FORM) {
      return;
    }
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ── PopScope ───────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Dirty tracking ─────────────────────────────────────────────────────────────
  void _checkForChanges() {
    if (deliveryNote.value == null) return;
    if (mode == 'new') { isDirty.value = true; return; }
    if (deliveryNote.value?.docstatus != 0) { isDirty.value = false; return; }
    final tempNote = DeliveryNote(
      name:        deliveryNote.value!.name,
      customer:    deliveryNote.value!.customer,
      grandTotal:  deliveryNote.value!.grandTotal,
      postingDate: deliveryNote.value!.postingDate,
      modified:    deliveryNote.value!.modified,
      creation:    deliveryNote.value!.creation,
      status:      deliveryNote.value!.status,
      currency:    deliveryNote.value!.currency,
      items:       deliveryNote.value!.items,
      poNo:        deliveryNote.value!.poNo,
      totalQty:    deliveryNote.value!.totalQty,
      docstatus:   deliveryNote.value!.docstatus,
      setWarehouse: setWarehouse.value,
    );
    isDirty.value = jsonEncode(tempNote.toJson()) != _originalJson;
  }

  void _updateOriginalState(DeliveryNote note) {
    _originalJson = jsonEncode(note.toJson());
    isDirty.value = false;
  }

  // ── Data fetching ────────────────────────────────────────────────────────────
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

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    final now = DateTime.now();
    deliveryNote.value = DeliveryNote(
      name:        'New Delivery Note',
      customer:    posUploadCustomer ?? '',
      grandTotal:  0.0,
      postingDate: now.toString().split(' ')[0],
      modified:    '',
      creation:    now.toString(),
      status:      'Draft',
      currency:    'AED',
      items:       [],
      poNo:        posUploadNameArg,
      totalQty:    0.0,
      docstatus:   0,
      setWarehouse: '',
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
    isDirty.value   = true;
    _originalJson   = '';
    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value  = note;
        setWarehouse.value  = note.setWarehouse;
        _updateOriginalState(note);
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        showBanner('Failed to fetch delivery note', type: BannerType.error);
      }
    } catch (e) {
      showBanner('Failed to load data: $e', type: BannerType.error);
    } finally {
      isLoading.value = false;
    }
  }

  // ── OptimisticLockingMixin contract ──────────────────────────────────────────────
  @override
  Future<void> reloadDocument() async {
    await fetchDeliveryNote();
    isStale.value = false;
    showBanner('Document reloaded successfully', type: BannerType.success);
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      log('[DN:fetchPosUpload] error: $e', name: 'DN');
    }
  }

  // ── POS qty-cap helpers ────────────────────────────────────────────────────────

  /// Returns the POS Upload qty cap for [serial] (the idx string),
  /// or [double.infinity] when there is no POS context.
  double posQtyCapForSerial(String serial) {
    final idx = int.tryParse(serial);
    if (idx == null || posUpload.value == null) return double.infinity;
    return posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == idx)
            ?.quantity ??
        double.infinity;
  }

  /// Returns the qty already recorded on this DN for [serial],
  /// optionally excluding a specific row being edited ([excludeItemName]).
  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (deliveryNote.value?.items ?? [])
        .where((i) =>
            (i.customInvoiceSerialNumber ?? '0') == serial &&
            i.name != excludeItemName)
        .fold(0.0, (sum, i) => sum + i.qty);
  }

  /// Returns the live remaining qty for [serial] against the POS Upload cap.
  ///
  /// Formula:
  ///   Remaining = posQtyCapForSerial(serial) − scannedQtyForSerial(serial)
  ///
  /// Returns [double.infinity] when there is no POS context so callers
  /// require no POS-entry guard before calling.
  double remainingQtyForSerial(String serial) {
    final cap = posQtyCapForSerial(serial);
    if (cap == double.infinity) return double.infinity;
    final used = scannedQtyForSerial(serial);
    return (cap - used).clamp(0.0, cap);
  }

  // ── Item sheet orchestration ──────────────────────────────────────────────────
  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    double   initialMaxQty = 0.0,
    DeliveryNoteItem? editingItem,
  }) async {
    if (editingItem != null) {
      if (editingItem.batchNo != null && editingItem.batchNo!.contains('-')) {
        currentScannedEan = editingItem.batchNo!.split('-').first;
      } else {
        currentScannedEan = '';
      }
    }

    final child = Get.put(DeliveryNoteItemFormController());
    child.initialise(
      parent:        this,
      code:          itemCode,
      name:          itemName,
      batchNo:       batchNo,
      initialMaxQty: initialMaxQty,
      editingItem:   editingItem,
      scannedEan8:   currentScannedEan,
    );

    child.setupAutoSubmit(
      enabled:      _storageService.getAutoSubmitEnabled(),
      delaySeconds: _storageService.getAutoSubmitDelay(),
      isSheetOpen:  isItemSheetOpen,
      isSubmittable: () => (deliveryNote.value?.docstatus ?? 1) == 0,
      onAutoSubmit: () async {
        isAddingItem.value = true;
        try {
          await child.submit();
          isDirty.value = true;
          await saveDeliveryNote();
        } finally {
          isAddingItem.value = false;
        }
        final nav = Get.key.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
      },
    );

    isItemSheetOpen.value = true;
    log('[DN:_openItemSheet] CHECKPOINT-3 isItemSheetOpen → true', name: 'DN');

    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize:     0.4,
        maxChildSize:     0.95,
        builder: (context, sc) {
          Future<void> openRackPicker() async {
            final tag =
                'rack_picker_dn_${DateTime.now().microsecondsSinceEpoch}';
            final pickerCtrl =
                Get.put(RackPickerController(), tag: tag);

            unawaited(pickerCtrl.load(
              itemCode:     child.itemCode.value,
              batchNo:      child.batchController.text,
              warehouse:    child.resolvedWarehouse ?? '',
              requestedQty:
                  double.tryParse(child.qtyController.text) ?? 0.0,
              currentRack:  child.rackController.text,
              fallbackMap:  child.rackStockMap,
            ));

            await Get.bottomSheet(
              RackPickerSheet(
                pickerTag: tag,
                onSelected: (rack) {
                  child.rackController.text = rack;
                  child.validateRack(rack);
                },
              ),
              isScrollControlled: true,
            );

            if (Get.isRegistered<RackPickerController>(tag: tag)) {
              Get.delete<RackPickerController>(tag: tag);
            }
          }

          Future<void> onSubmit() async {
            isAddingItem.value = true;
            try {
              final bool saved = await child.submitWithFeedback();
              if (saved) {
                isDirty.value = true;
                await saveDeliveryNote();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            } finally {
              isAddingItem.value = false;
            }
          }

          return UniversalItemFormSheet(
            controller:       child,
            scrollController: sc,
            onSubmit:         onSubmit,
            onScan:           (code) => scanBarcode(code),
            customFields: [
              SharedSerialField(
                controller:  child,
                accentColor: Colors.blueGrey,
              ),
              SharedBatchField(
                c:           child,
                accentColor: Colors.purple,
                editMode:    true,
                fieldKey:    'dn_batch_field',
              ),
              SharedRackField(
                c:           child,
                accentColor: Colors.orange,
                editMode:    true,
                onPickerTap: openRackPicker,
              ),
            ],
          );
        },
      ),
      isScrollControlled: true,
    );

    isItemSheetOpen.value = false;
    log('[DN:_openItemSheet] CHECKPOINT-3B isItemSheetOpen → false', name: 'DN');
    barcodeController.clear();
    if (Get.isRegistered<DeliveryNoteItemFormController>()) {
      Get.delete<DeliveryNoteItemFormController>();
    }
  }

  // ── Public entry points ────────────────────────────────────────────────────
  Future<void> editItem(DeliveryNoteItem item) async {
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;
    double fetchedQty = 0.0;
    try {
      if (item.batchNo != null) {
        String? targetWh = setWarehouse.value;
        if (item.rack != null && item.rack!.isNotEmpty) {
          try {
            final rackRes = await _apiProvider.getDocument('Rack', item.rack!);
            if (rackRes.statusCode == 200 && rackRes.data['data'] != null) {
              targetWh = rackRes.data['data']['warehouse'];
            }
          } catch (_) {}
        }
        final balRes = await _apiProvider.getBatchWiseBalance(
          item.itemCode,
          item.batchNo!,
          warehouse: targetWh,
        );
        if (balRes.statusCode == 200 && balRes.data['message'] != null) {
          final result = balRes.data['message']['result'];
          if (result is List && result.isNotEmpty) {
            fetchedQty =
                (result.first['balance_qty'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (_) {
      fetchedQty = 999;
    } finally {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    }

    await _openItemSheet(
      itemCode:      item.itemCode,
      itemName:      item.itemName ?? '',
      batchNo:       item.batchNo,
      initialMaxQty: fetchedQty,
      editingItem:   item,
    );
  }

  // ── Item CRUD ──────────────────────────────────────────────────────────────

  void updateItemLocally(
      String itemNameID, double qty, String rack,
      String? batchNo, String? invoiceSerial) {
    final serial = invoiceSerial ?? '0';
    final items  = deliveryNote.value?.items.toList() ?? [];
    final idx    = items.indexWhere((i) => i.name == itemNameID);
    if (idx == -1) return;

    // ── Hard block: POS qty cap ──────────────────────────────────────────────
    if (serial != '0' && posUpload.value != null) {
      final cap        = posQtyCapForSerial(serial);
      final othersQty  = scannedQtyForSerial(serial,
          excludeItemName: itemNameID);
      if (othersQty + qty > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(serial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(serial),
          itemName:   posItem?.itemName ?? items[idx].itemName ?? '',
          scannedQty: othersQty,
          capQty:     cap,
        );
        return;
      }
    }

    items[idx] = items[idx].copyWith(
        qty: qty, rack: rack, batchNo: batchNo,
        customInvoiceSerialNumber: invoiceSerial);
    deliveryNote.update((val) => val?.items.assignAll(items));
    _triggerItemFeedback(items[idx].itemCode, serial);
  }

  void addItemLocally(
      String itemCode, String itemName, double qty, String rack,
      String? batchNo, String? invoiceSerial) {
    final items  = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';

    // ── Hard block: POS qty cap ──────────────────────────────────────────────
    if (serial != '0' && posUpload.value != null) {
      final cap = posQtyCapForSerial(serial);

      // If this scan would merge into an existing row, exclude that
      // row's current qty from alreadyUsed to avoid double-counting.
      final existingIdx = items.indexWhere((i) =>
          i.itemCode == itemCode &&
          (i.batchNo ?? '') == (batchNo ?? '') &&
          (i.rack ?? '') == rack &&
          (i.customInvoiceSerialNumber ?? '0') == serial);
      final mergeQty = existingIdx != -1 ? items[existingIdx].qty : 0.0;
      final alreadyUsed  = scannedQtyForSerial(serial);
      final projectedTotal = alreadyUsed - mergeQty + qty;

      if (projectedTotal > cap) {
        final posItem = posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == int.tryParse(serial));
        GlobalDialog.showQtyCapExceeded(
          serialNo:   int.parse(serial),
          itemName:   posItem?.itemName ?? itemName,
          scannedQty: alreadyUsed - mergeQty,
          capQty:     cap,
        );
        return;
      }
    }

    final existingIdx = items.indexWhere((i) =>
        i.itemCode == itemCode &&
        (i.batchNo ?? '') == (batchNo ?? '') &&
        (i.rack ?? '') == rack &&
        (i.customInvoiceSerialNumber ?? '0') == serial);

    if (existingIdx != -1) {
      final existing = items[existingIdx];
      items[existingIdx] = existing.copyWith(qty: existing.qty + qty);
    } else {
      items.add(DeliveryNoteItem(
        name:    'local_${DateTime.now().millisecondsSinceEpoch}',
        itemCode: itemCode,
        qty:     qty,
        rate:    0.0,
        rack:    rack,
        batchNo: batchNo,
        customInvoiceSerialNumber: serial,
        itemName: itemName,
        creation: DateTime.now().toString(),
      ));
    }
    deliveryNote.update((val) => val?.items.assignAll(items));
    _triggerItemFeedback(itemCode, serial);
  }

  Future<void> confirmAndDeleteItem(DeliveryNoteItem item) async {
    GlobalDialog.showConfirmation(
      title:   'Delete Item?',
      message: 'Remove ${item.itemCode} from this note?',
      onConfirm: () async {
        _deleteItemLocally(item);
        await saveDeliveryNote();
      },
    );
  }

  void _deleteItemLocally(DeliveryNoteItem item) {
    final items = deliveryNote.value?.items.toList() ?? [];
    items.remove(item);
    deliveryNote.update((val) => val?.items.assignAll(items));
    _checkForChanges();
    showBanner('Item removed', type: BannerType.success);
  }

  // ── Save ────────────────────────────────────────────────────────────────────
  Future<void> saveDeliveryNote() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;
    isSaving.value      = true;
    customerError.value = null;
    try {
      final String docName = deliveryNote.value?.name ?? '';
      final bool   isNew   = docName == 'New Delivery Note' || docName.isEmpty;
      final Map<String, dynamic> data = deliveryNote.value!.toJson();
      data['set_warehouse'] = setWarehouse.value;

      if (isNew) {
        data['customer']     = deliveryNote.value!.customer;
        data['posting_date'] = deliveryNote.value!.postingDate;
        if (deliveryNote.value!.poNo != null) data['po_no'] = deliveryNote.value!.poNo;
        data['docstatus'] = 0;
      }

      final response = isNew
          ? await _apiProvider.createDocument('Delivery Note', data)
          : await _apiProvider.updateDocument('Delivery Note', docName, data);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final savedNote = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = savedNote;
        _updateOriginalState(savedNote);
        if (isNew) mode = 'edit';
        _setSaveResult(SaveResult.success);
        showBanner('Delivery Note Saved', type: BannerType.success);
      } else {
        _setSaveResult(SaveResult.error);
        showBanner(
          'Failed to save: ${response.data['exception'] ?? 'Unknown error'}',
          type: BannerType.error,
        );
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // Handled by OptimisticLockingMixin.
      } else {
        _setSaveResult(SaveResult.error);
        final msg = e.response?.data.toString() ?? e.message ?? '';
        if (msg.contains('Customer') && msg.contains('not found')) {
          customerError.value = 'Customer not found in the system';
        }
        showBanner('Save failed: ${e.message}', type: BannerType.error);
      }
    } catch (e) {
      _setSaveResult(SaveResult.error);
      final msg = e.toString();
      if (msg.contains('Customer') && msg.contains('not found')) {
        customerError.value = 'Customer not found in the system';
      }
      showBanner('Save failed: $e', type: BannerType.error);
    } finally {
      isSaving.value = false;
    }
  }

  // ── UX helpers ─────────────────────────────────────────────────────────────────
  void _triggerItemFeedback(String itemCode, String serial) {
    recentlyAddedItemCode.value = itemCode;
    recentlyAddedSerial.value   = serial;
    if (serial != '0' && serial.isNotEmpty) {
      expandedInvoice.value = serial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final item = deliveryNote.value?.items.firstWhereOrNull(
            (i) => i.itemCode == itemCode &&
                (i.customInvoiceSerialNumber ?? '0') == serial);
        if (item != null && item.name != null) {
          final key = itemKeys[item.name];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration:  const Duration(milliseconds: 500),
              curve:     Curves.easeInOut,
              alignment: 0.5,
            );
          }
        }
      });
    });
    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemCode.value = '';
      recentlyAddedSerial.value   = '';
    });
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value =
        expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value =
        expandedInvoice.value == key ? '' : key;
  }

  // ── Scan routing ─────────────────────────────────────────────────────────────────
  bool _validateHeaderBeforeScan() {
    if (deliveryNote.value == null) return false;
    if (deliveryNote.value!.customer.isEmpty) {
      GlobalSnackbar.error(
          message: 'Missing Customer: Please select a customer before scanning.');
      return false;
    }
    if (customerError.value != null) {
      GlobalSnackbar.error(
          message: 'Invalid Customer: ${customerError.value}');
      return false;
    }
    return true;
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    if (!_validateHeaderBeforeScan()) {
      return;
    }

    // ── INSIDE-SHEET PATH ──────────────────────────────────────────────────────────────────────────────────────
    if (isItemSheetOpen.value) {
      barcodeController.clear();

      final bool childRegistered =
          Get.isRegistered<DeliveryNoteItemFormController>();

      if (!childRegistered) {
        return;
      }

      final child = Get.find<DeliveryNoteItemFormController>();
      final String? contextEan =
          child.currentScannedEan.isNotEmpty ? child.currentScannedEan : null;

      final result =
          await _scanService.processScan(barcode, contextItemCode: contextEan);


      if (result.type == ScanType.rack && result.rackId != null) {
        child.rackController.text = result.rackId!;
        child.validateRack(result.rackId!);
      } else if (result.type == ScanType.batch || result.type == ScanType.item) {
        final candidateBatch = result.batchNo;
        if (candidateBatch != null && candidateBatch.isNotEmpty) {
          child.batchController.text = candidateBatch;
          child.validateBatch(candidateBatch);
        } else {
          GlobalSnackbar.error(
              message: 'Scan the item EAN first, then scan the batch suffix.');
        }
      } else if (result.type == ScanType.error) {
        GlobalSnackbar.error(message: result.message ?? 'Invalid Scan');
      } else {
      }
      return;
    }

    // ── OUTSIDE-SHEET PATH ────────────────────────────────────────────────────────────────────────────────────────
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);

      if (result.isSuccess && result.itemData != null) {
        if (result.rawCode.contains('-') &&
            !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-').first;
        } else {
          currentScannedEan = result.rawCode;
        }

        final itemData = result.itemData!;
        double  maxQty          = 0.0;
        String? resolvedBatchNo = result.batchNo;

        try {
          final batchNo = resolvedBatchNo;
          if (batchNo != null && batchNo.isNotEmpty) {
            final balRes = await _apiProvider.getBatchWiseBalance(
              itemData.itemCode,
              batchNo,
              warehouse: setWarehouse.value,
            );
            if (balRes.statusCode == 200 &&
                balRes.data['message']?['result'] != null) {
              final list = balRes.data['message']['result'] as List;
              if (list.isNotEmpty) {
                maxQty          = (list[0]['balance_qty'] as num?)?.toDouble() ?? 0.0;
                resolvedBatchNo ??= list[0]['batch_no'] as String?;
              }
            }
          }
        } catch (_) {
          maxQty = 0.0;
        }

        isScanning.value = false;
        barcodeController.clear();

        await _openItemSheet(
          itemCode:      itemData.itemCode,
          itemName:      itemData.itemName,
          batchNo:       resolvedBatchNo,
          initialMaxQty: maxQty,
        );
      } else if (result.type == ScanType.multiple) {
        GlobalSnackbar.warning(
            message: 'Multiple items found. Please search manually.');
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Grouped items + filter helpers ───────────────────────────────────────────────
  Map<String, List<DeliveryNoteItem>> get groupedItems {
    if (deliveryNote.value == null || deliveryNote.value!.items.isEmpty) {
      return {};
    }
    return groupBy(deliveryNote.value!.items,
        (DeliveryNoteItem i) => i.customInvoiceSerialNumber ?? '0');
  }

  int get allCount => posUpload.value?.items.length ?? 0;

  int get completedCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serial =
          (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final qty =
          (groups[serial] ?? []).fold(0.0, (s, i) => s + i.qty);
      return qty >= posItem.quantity;
    }).length;
  }

  int get pendingCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serial =
          (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final qty =
          (groups[serial] ?? []).fold(0.0, (s, i) => s + i.qty);
      return qty < posItem.quantity;
    }).length;
  }

  void setFilter(String filter) => itemFilter.value = filter;
}
