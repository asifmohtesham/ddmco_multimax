import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/mixins/controller_feedback_mixin.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';
import 'package:multimax/app/shared/item_sheet/widgets/item_sheet_widgets.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_controller.dart';
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/derived_warehouse_label.dart';

// Child sheet controller
import 'delivery_note_item_form_controller.dart';

class DeliveryNoteFormController extends GetxController
    with OptimisticLockingMixin, ControllerFeedbackMixin {
  final DeliveryNoteProvider  _provider          = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider     _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider           _apiProvider       = Get.find<ApiProvider>();
  final WorkOrderProvider     _woProvider        = Get.find<WorkOrderProvider>();
  final ScanService           _scanService       = Get.find<ScanService>();
  final StorageService        _storageService    = Get.find<StorageService>();
  final DataWedgeService      _dataWedgeService  = Get.find<DataWedgeService>();

  final String  name = Get.arguments['name'];
  String        mode = Get.arguments['mode'];

  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg  = Get.arguments['posUploadName'];

  // ── Document-level state ──────────────────────────────────────────────────
  var isLoading    = true.obs;
  var isScanning   = false.obs;
  var isAddingItem = false.obs;
  var isSaving     = false.obs;
  var isDirty      = false.obs;
  String _originalJson = '';

  // ── Save result state machine ─────────────────────────────────────────────
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

  // ── Sheet-open + item-edit loading flags ──────────────────────────────────
  var isItemSheetOpen    = false.obs;
  var isLoadingItemEdit  = false.obs;
  var loadingForItemName = RxnString();

  // ── Warehouse ─────────────────────────────────────────────────────────────
  var warehouses           = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse         = RxnString();
  final _derivedWarehousePlaceholder = RxnString();

  // ── Customer-level error ──────────────────────────────────────────────────
  var customerError = RxnString();

  // ── EAN scan context ──────────────────────────────────────────────────────
  String currentScannedEan = '';

  // ── Persistent scan worker ────────────────────────────────────────────────
  Worker? _scanWorker;

  // ── items convenience getter ──────────────────────────────────────────────
  List<DeliveryNoteItem> get items => deliveryNote.value?.items ?? [];

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();
    ever(setWarehouse, (_) => checkForChanges());
    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[DN:onInit] _scanWorker registered on DataWedgeService.scannedCode',
        name: 'DN');

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDocument();
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

  // ── Raw scan entry point ──────────────────────────────────────────────────
  void _onRawScan(String code) {
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.DELIVERY_NOTE_FORM) return;
    if (isItemSheetOpen.value) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }


  // ── PopScope ──────────────────────────────────────────────────────────────
  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  // ── Dirty tracking ────────────────────────────────────────────────────────
  void checkForChanges() {
    if (deliveryNote.value == null) return;
    if (mode == 'new') { isDirty.value = true; return; }
    if (deliveryNote.value?.docstatus != 0) { isDirty.value = false; return; }
    final tempNote = DeliveryNote(
      name:         deliveryNote.value!.name,
      customer:     deliveryNote.value!.customer,
      grandTotal:   deliveryNote.value!.grandTotal,
      postingDate:  deliveryNote.value!.postingDate,
      modified:     deliveryNote.value!.modified,
      creation:     deliveryNote.value!.creation,
      status:       deliveryNote.value!.status,
      currency:     deliveryNote.value!.currency,
      items:        deliveryNote.value!.items,
      poNo:         deliveryNote.value!.poNo,
      totalQty:     deliveryNote.value!.totalQty,
      docstatus:    deliveryNote.value!.docstatus,
      setWarehouse: setWarehouse.value,
    );
    isDirty.value = jsonEncode(tempNote.toJson()) != _originalJson;
  }

  void _updateOriginalState(DeliveryNote note) {
    _originalJson = jsonEncode(note.toJson());
    isDirty.value = false;
  }

  // ── Data fetching ─────────────────────────────────────────────────────────
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
    await _validateCustomerOnOpen();
    isDirty.value   = true;
    _originalJson   = '';
    isLoading.value = false;
  }

  Future<void> fetchDocument() async {
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
        await _validateCustomerOnOpen();
      } else {
        showBanner('Failed to fetch delivery note', type: BannerType.error);
      }
    } catch (e) {
      showBanner('Failed to load data: $e', type: BannerType.error);
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
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

  // ── POS qty-cap helpers ───────────────────────────────────────────────────
  double posQtyCapForSerial(String serial) {
    final idx = int.tryParse(serial);
    if (idx == null || posUpload.value == null) return double.infinity;
    return posUpload.value!.items
            .firstWhereOrNull((i) => i.idx == idx)
            ?.quantity ??
        double.infinity;
  }

  double scannedQtyForSerial(String serial, {String? excludeItemName}) {
    return (deliveryNote.value?.items ?? [])
        .where((i) {
          return (i.customInvoiceSerialNumber) == serial &&
              (excludeItemName == null || i.name != excludeItemName);
        })
        .fold(0.0, (sum, i) {
          debugPrint('i.qty: ${i.qty}');
          return sum + i.qty;
        });
  }

  double remainingQtyForSerial(String serial) {
    final cap = posQtyCapForSerial(serial);
    if (cap == double.infinity) return double.infinity;
    final used = scannedQtyForSerial(serial);
    return (cap - used).clamp(0.0, cap);
  }

  // ── Item sheet orchestration ──────────────────────────────────────────────
  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  variantOf,
    DeliveryNoteItem? editingItem,
  }) async {
    if (editingItem != null) {
      if (editingItem.batchNo != null && editingItem.batchNo!.contains('-')) {
        currentScannedEan = editingItem.batchNo!.split('-').first;
      } else {
        currentScannedEan = '';
      }
    }

    final child = Get.put(
      DeliveryNoteItemFormController(),
      permanent: true,
    );
    child.initialise(
      parent:      this,
      code:        itemCode,
      name:        itemName,
      batchNo:     batchNo,
      variantOf:   variantOf ?? editingItem?.customVariantOf,
      scannedEan8: currentScannedEan,
      editingItem: editingItem,
    );

    const rackPickerTag = 'dn_rack_picker';

    isItemSheetOpen.value = true;
    child.initBarcodeListener();
    await Get.bottomSheet(
      UniversalItemFormSheet(
        controller:       child,
        scrollController: child.sheetScrollController,
        customFields: [
          _CheckWoButton(
            itemCode: itemCode,
            fetchWorkOrders: () => fetchWorkOrdersForItem(itemCode),
          ),
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
          DerivedWarehouseLabel(
            itemWarehouse:    child.itemWarehouse,
            derivedWarehouse: _derivedWarehousePlaceholder,
            headerWarehouse:  setWarehouse,
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
    child.disposeBarcodeListener();
    isItemSheetOpen.value = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      child.disposeControllers();
      Get.delete<DeliveryNoteItemFormController>(force: true);
      log('[DN:_openItemSheet] post-frame teardown complete', name: 'DN');
    });
  }

  void _handleCustomerNotFound(String customer) {
    customerError.value = 'Customer not found in the system';
    GlobalDialog.showCustomerNotFound(customer: customer);
  }

  Future<void> _validateCustomerOnOpen() async {
    final customer = deliveryNote.value?.customer ?? '';
    if (customer.isEmpty) return;
    try {
      final response = await _apiProvider.getDocument('Customer', customer);
      if (response.statusCode != 200 || response.data['data'] == null) {
        _handleCustomerNotFound(customer);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _handleCustomerNotFound(customer);
      }
      // Network/other errors: don't block the form; save will surface them.
    }
  }

  // ── Work Order lookup for item (Item #7A) ─────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchWorkOrdersForItem(String itemCode) async {
    try {
      final res = await _woProvider.getWorkOrders(
        filters: {
          'production_item': itemCode,
          'status': ['in', 'Not Started,In Process'],
        },
        limit: 5,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> saveDocument() async {
    if (isSaving.value) return;
    isSaving.value = true;
    try {
      final note = deliveryNote.value;
      if (note == null) return;

      final payload = note.toJson();
      payload['set_warehouse'] = setWarehouse.value ?? '';

      Response response;
      if (mode == 'new') {
        response = await _apiProvider.createDocument('Delivery Note', payload);
      } else {
        response = await _apiProvider.updateDocument('Delivery Note', name, payload);
      }

      if (response.statusCode == 200 && response.data['data'] != null) {
        final saved = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = saved;
        setWarehouse.value = saved.setWarehouse;
        _updateOriginalState(saved);
        customerError.value = null;
        if (mode == 'new') {
          mode = 'edit';
          Get.parameters['mode'] = 'edit';
        }
        _setSaveResult(SaveResult.success);
      } else {
        _setSaveResult(SaveResult.error);
        showBanner('Failed to save delivery note', type: BannerType.error);
      }
    } on DioException catch (e) {
      _setSaveResult(SaveResult.error);
      final int? statusCode = e.response?.statusCode;
      final String rawError = (() {
        final data = e.response?.data;
        if (data is Map) return data.toString();
        return data?.toString() ?? '';
      })();

      final bool isCustomerNotFound =
          (statusCode == 417 || statusCode == 400) &&
          (rawError.toLowerCase().contains('customer') ||
          rawError.toLowerCase().contains('does not exist') ||
          rawError.toLowerCase().contains('link validation'));

      if (isCustomerNotFound) {
        _handleCustomerNotFound(
            deliveryNote.value?.customer ?? posUploadCustomer ?? '');
      } else {
        final message = e.response?.data is Map
            ? (e.response!.data['exception'] ??
               e.response!.data['message'] ??
               'An unexpected error occurred.')
            : 'An unexpected error occurred.';
        showBanner(message.toString(), type: BannerType.error);
      }
    } catch (e) {
      _setSaveResult(SaveResult.error);
      showBanner('An unexpected error occurred: $e', type: BannerType.error);
    } finally {
      isSaving.value = false;
    }
  }

  bool _validateHeaderBeforeScan() {
    final note = deliveryNote.value;
    if (note == null) {
      GlobalSnackbar.error(message: 'Delivery note not loaded yet.');
      return false;
    }
    if (note.customer.isEmpty) {
      customerError.value = 'Customer is required before scanning.';
      GlobalSnackbar.error(
          message: 'Please set a customer before scanning items.');
      return false;
    }
    customerError.value = null;
    return true;
  }

  Future<void> scanBarcode(String barcode) async {
    if (!_validateHeaderBeforeScan()) return;
    if (isScanning.value || isAddingItem.value) return;
    if (barcode.isEmpty) return;

    final cleanBarcode = barcode.trim();
    isScanning.value = true;

    try {
      final result = await _scanService.processScan(cleanBarcode);

      switch (result.type) {
        case ScanType.item:
          currentScannedEan = result.rawCode ?? '';
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

  // ── Item CRUD ─────────────────────────────────────────────────────────────
  Future<void> addItem(DeliveryNoteItem newItem) async {
    deliveryNote.value?.items.add(newItem);
    deliveryNote.refresh();
    checkForChanges();
    recentlyAddedItemCode.value = newItem.itemCode;
    recentlyAddedSerial.value   = newItem.customInvoiceSerialNumber ?? '';
    Future.delayed(const Duration(seconds: 2), () {
      if (recentlyAddedItemCode.value == newItem.itemCode) {
        recentlyAddedItemCode.value = '';
      }
    });
    _scrollToItem(newItem.name ?? newItem.itemCode);
    if (mode == 'edit') await saveDocument();
  }

  Future<void> updateItem(DeliveryNoteItem updatedItem) async {
    final items = deliveryNote.value?.items ?? [];
    final idx   = items.indexWhere((i) => i.name == updatedItem.name);
    if (idx != -1) {
      items[idx] = updatedItem;
      deliveryNote.refresh();
      checkForChanges();
    }
    if (mode == 'edit') await saveDocument();
  }

  Future<void> deleteItem(DeliveryNoteItem item) async {
    final confirmed = await GlobalDialog.confirm(
      title:        'Remove Item',
      message:      'Remove "${item.itemName}" from this delivery note?',
      confirmText:  'Remove',
      confirmColor: Colors.red,
      icon:         Icons.delete_outline,
    );
    if (confirmed != true) return;
    deliveryNote.value?.items.removeWhere((i) => i.name == item.name);
    deliveryNote.refresh();
    checkForChanges();
    if (mode == 'edit') await saveDocument();
  }

  Future<void> editItem(DeliveryNoteItem item) async {
    if (isLoadingItemEdit.value) return;
    isLoadingItemEdit.value  = true;
    loadingForItemName.value = item.name;

    await _openItemSheet(
      itemCode:    item.itemCode,
      itemName:    item.itemName ?? item.itemCode,
      batchNo:     item.batchNo,
      editingItem: item,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      isLoadingItemEdit.value  = false;
      loadingForItemName.value = null;
    });
  }

  void _scrollToItem(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final globalKey = itemKeys[key];
      if (globalKey?.currentContext != null) {
        Scrollable.ensureVisible(
          globalKey!.currentContext!,
          duration: const Duration(milliseconds: 400),
          curve:    Curves.easeInOut,
        );
      }
    });
  }

  void setFilter(String filter) => itemFilter.value = filter;

  int get allCount => posUpload.value?.items.length ??
      (deliveryNote.value?.items.length ?? 0);

  int get pendingCount {
    if (posUpload.value == null) return 0;
    return posUpload.value!.items.where((posItem) {
      final serial = posItem.idx.toString();
      final used   = groupedItems[serial]
              ?.fold(0.0, (s, i) => s + i.qty) ?? 0.0;
      return used < posItem.quantity;
    }).length;
  }

  int get completedCount {
    if (posUpload.value == null) return 0;
    return posUpload.value!.items.where((posItem) {
      final serial = posItem.idx.toString();
      final used   = groupedItems[serial]
              ?.fold(0.0, (s, i) => s + i.qty) ?? 0.0;
      return used >= posItem.quantity;
    }).length;
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    final map = <String, List<DeliveryNoteItem>>{};
    for (final item in deliveryNote.value?.items ?? []) {
      final serial = item.customInvoiceSerialNumber ?? '0';
      map.putIfAbsent(serial, () => []).add(item);
    }
    return map;
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value =
        expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }
}

// ── Multiple-match sheet (private widget) ─────────────────────────────────────

class _MultipleMatchSheet extends StatelessWidget {
  const _MultipleMatchSheet({
    required this.candidates,
    required this.parent,
  });

  final List<Item> candidates;
  final DeliveryNoteFormController parent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Multiple Items Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the item you want to add:',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ...candidates.map((item) => ListTile(
                  title: Text(item.itemName ?? item.itemCode),
                  subtitle: Text(item.itemCode),
                  onTap: () async {
                    Get.back();
                    await parent._openItemSheet(
                      itemCode:  item.itemCode,
                      itemName:  item.itemName ?? item.itemCode,
                      variantOf: item.variantOf,
                    );
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ── Check WO button widget ─────────────────────────────────────────────────────
// Shows active Work Orders for the item directly in the DN item sheet.

class _CheckWoButton extends StatefulWidget {
  final String itemCode;
  final Future<List<Map<String, dynamic>>> Function() fetchWorkOrders;
  const _CheckWoButton({required this.itemCode, required this.fetchWorkOrders});

  @override
  State<_CheckWoButton> createState() => _CheckWoButtonState();
}

class _CheckWoButtonState extends State<_CheckWoButton> {
  bool _loading   = false;
  bool _expanded  = false;
  List<Map<String, dynamic>> _wos = [];

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final results = await widget.fetchWorkOrders();
    if (!mounted) return;
    setState(() {
      _loading  = false;
      _expanded = true;
      _wos      = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _expanded ? () => setState(() => _expanded = false) : _load,
          icon: _loading
              ? SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                )
              : Icon(_expanded ? Icons.expand_less : Icons.precision_manufacturing_outlined, size: 18),
          label: Text(_expanded ? 'Hide Work Orders' : 'Check Work Orders'),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            visualDensity: VisualDensity.compact,
            textStyle: text.labelMedium,
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          if (_wos.isEmpty)
            Text('No active Work Orders for this item.',
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant))
          else
            ..._wos.map((wo) => _WoInfoTile(wo: wo, cs: cs, text: text)),
        ],
      ],
    );
  }
}

class _WoInfoTile extends StatelessWidget {
  final Map<String, dynamic> wo;
  final ColorScheme cs;
  final TextTheme text;
  const _WoInfoTile({required this.wo, required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    final name   = wo['name']   as String? ?? '';
    final status = wo['status'] as String? ?? '';
    final qty    = (wo['qty']   as num?)?.toStringAsFixed(0) ?? '0';
    final done   = (wo['produced_qty'] as num?)?.toStringAsFixed(0) ?? '0';

    return InkWell(
      onTap: () => Get.toNamed(
        AppRoutes.WORK_ORDER_FORM,
        arguments: {'name': name, 'mode': 'view'},
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('$done / $qty  ·  $status',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
