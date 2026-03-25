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
import 'package:multimax/app/shared/item_sheet/widgets/shared_serial_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_batch_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_rack_field.dart';
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

  // ── Document-level state ───────────────────────────────────────────────────────────
  var isLoading    = true.obs;
  var isScanning   = false.obs;
  var isAddingItem = false.obs;
  var isSaving     = false.obs;
  var isDirty      = false.obs;
  String _originalJson = '';

  // ── Save result state machine (mirrors SE/PR) ────────────────────────────────────────
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

  // ── Sheet-open + item-edit loading flags ───────────────────────────────────────────────
  var isItemSheetOpen    = false.obs;
  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // ── Warehouse ─────────────────────────────────────────────────────────────────────────
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse         = RxnString();

  // ── Item warehouse (derived from rack — still needed by child controller) ──
  var bsItemWarehouse = RxnString();

  // ── Customer-level error ───────────────────────────────────────────────────────────
  var customerError = RxnString();

  // ── S1: EAN scan context for inside-sheet scan routing ────────────────────
  String currentScannedEan = '';

  // ── Persistent scan worker ──────────────────────────────────────────────────────
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
    disposeFeedback(); // ControllerFeedbackMixin — cancels auto-dismiss timer
    log('[DN:onClose] _scanWorker disposed', name: 'DN');
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  // ── Raw scan entry point ───────────────────────────────────────────────────
  void _onRawScan(String code) {
    log('[DN:_onRawScan] CHECKPOINT-1 code="$code" currentRoute=${Get.currentRoute}',
        name: 'DN');
    if (code.isEmpty) {
      log('[DN:_onRawScan] CHECKPOINT-1A empty code — ignored', name: 'DN');
      return;
    }
    if (Get.currentRoute != AppRoutes.DELIVERY_NOTE_FORM) {
      log('[DN:_onRawScan] CHECKPOINT-1B wrong route (${Get.currentRoute}) — ignored',
          name: 'DN');
      return;
    }
    final clean = code.trim();
    log('[DN:_onRawScan] CHECKPOINT-2 forwarding clean="$clean" to scanBarcode',
        name: 'DN');
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ── PopScope ────────────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Dirty tracking ──────────────────────────────────────────────────────────────────
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

  // ── Data fetching ────────────────────────────────────────────────────────────────
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

  // ── Item sheet orchestration ─────────────────────────────────────────────────────────────
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
          // ── Rack picker helper ────────────────────────────────────────────────────────────────
          // Opens RackPickerSheet for the DN rack field.
          // Unique tag isolates this picker from any other that may be
          // open concurrently (e.g. if the sheet is rapidly re-opened).
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

  // ── Public entry points ─────────────────────────────────────────────────────────────
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
    final items = deliveryNote.value?.items.toList() ?? [];
    final idx   = items.indexWhere((i) => i.name == itemNameID);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(
          qty: qty, rack: rack, batchNo: batchNo,
          customInvoiceSerialNumber: invoiceSerial);
      deliveryNote.update((val) => val?.items.assignAll(items));
      _triggerItemFeedback(items[idx].itemCode, invoiceSerial ?? '0');
    }
  }

  void addItemLocally(
      String itemCode, String itemName, double qty, String rack,
      String? batchNo, String? invoiceSerial) {
    final items  = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';

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

  // ── Save ─────────────────────────────────────────────────────────────────────────
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
        // Handled by OptimisticLockingMixin — shows GlobalDialog, not a banner.
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

  // ── UX helpers ───────────────────────────────────────────────────────────────────────
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

  // ── Scan routing ───────────────────────────────────────────────────────────────────────
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
    log('[DN:scanBarcode] CHECKPOINT-4 barcode="$barcode" isItemSheetOpen=${isItemSheetOpen.value}',
        name: 'DN');

    if (!_validateHeaderBeforeScan()) {
      log('[DN:scanBarcode] CHECKPOINT-4A header validation failed — aborted',
          name: 'DN');
      return;
    }

    // ── INSIDE-SHEET PATH ─────────────────────────────────────────────────────────────────────
    if (isItemSheetOpen.value) {
      log('[DN:scanBarcode] CHECKPOINT-5 inside-sheet path entered for barcode="$barcode"',
          name: 'DN');
      barcodeController.clear();

      final bool childRegistered =
          Get.isRegistered<DeliveryNoteItemFormController>();
      log('[DN:scanBarcode] CHECKPOINT-5A childRegistered=$childRegistered',
          name: 'DN');

      if (!childRegistered) {
        log('[DN:scanBarcode] CHECKPOINT-5B child NOT registered — scan dropped',
            name: 'DN');
        return;
      }

      final child = Get.find<DeliveryNoteItemFormController>();
      final String? contextEan =
          child.currentScannedEan.isNotEmpty ? child.currentScannedEan : null;

      log('[DN:scanBarcode] CHECKPOINT-5C contextEan=$contextEan', name: 'DN');
      final result =
          await _scanService.processScan(barcode, contextItemCode: contextEan);

      log('[DN:scanBarcode] CHECKPOINT-5D result: type=${result.type} batchNo=${result.batchNo}',
          name: 'DN');

      if (result.type == ScanType.rack && result.rackId != null) {
        log('[DN:scanBarcode] CHECKPOINT-5E routing to rack: ${result.rackId}',
            name: 'DN');
        child.rackController.text = result.rackId!;
        child.validateRack(result.rackId!);
      } else if (result.type == ScanType.batch || result.type == ScanType.item) {
        final candidateBatch = result.batchNo;
        log('[DN:scanBarcode] CHECKPOINT-5F batch path: candidateBatch=$candidateBatch',
            name: 'DN');
        if (candidateBatch != null && candidateBatch.isNotEmpty) {
          child.batchController.text = candidateBatch;
          log('[DN:scanBarcode] CHECKPOINT-5G batchController.text → "${child.batchController.text}"',
              name: 'DN');
          child.validateBatch(candidateBatch);
        } else {
          log('[DN:scanBarcode] CHECKPOINT-5H candidateBatch null/empty', name: 'DN');
          GlobalSnackbar.error(
              message: 'Scan the item EAN first, then scan the batch suffix.');
        }
      } else if (result.type == ScanType.error) {
        log('[DN:scanBarcode] CHECKPOINT-5I ScanType.error: ${result.message}',
            name: 'DN');
        GlobalSnackbar.error(message: result.message ?? 'Invalid Scan');
      } else {
        log('[DN:scanBarcode] CHECKPOINT-5J unhandled type=${result.type}',
            name: 'DN');
      }
      return;
    }

    // ── OUTSIDE-SHEET PATH ───────────────────────────────────────────────────────────────────
    log('[DN:scanBarcode] CHECKPOINT-6 outside-sheet path for barcode="$barcode"',
        name: 'DN');
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      log('[DN:scanBarcode] CHECKPOINT-6A outside result: type=${result.type} item=${result.itemData?.itemCode}',
          name: 'DN');

      if (result.isSuccess && result.itemData != null) {
        if (result.rawCode.contains('-') &&
            !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-').first;
        } else {
          currentScannedEan = result.rawCode;
        }
        log('[DN:scanBarcode] CHECKPOINT-6B currentScannedEan → "$currentScannedEan"',
            name: 'DN');

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

        log('[DN:scanBarcode] CHECKPOINT-6C opening item sheet for ${itemData.itemCode}',
            name: 'DN');
        await _openItemSheet(
          itemCode:      itemData.itemCode,
          itemName:      itemData.itemName,
          batchNo:       resolvedBatchNo,
          initialMaxQty: maxQty,
        );
      } else if (result.type == ScanType.multiple) {
        log('[DN:scanBarcode] CHECKPOINT-6D ScanType.multiple', name: 'DN');
        GlobalSnackbar.warning(
            message: 'Multiple items found. Please search manually.');
      } else {
        log('[DN:scanBarcode] CHECKPOINT-6E no item found: ${result.message}',
            name: 'DN');
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      log('[DN:scanBarcode] CHECKPOINT-6F exception: $e', name: 'DN');
      GlobalSnackbar.error(message: 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Grouped items + filter helpers ──────────────────────────────────────────────────
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
