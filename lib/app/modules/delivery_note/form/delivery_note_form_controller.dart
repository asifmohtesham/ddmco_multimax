import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'widgets/delivery_note_item_form_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

class DeliveryNoteFormController extends GetxController with OptimisticLockingMixin {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final StorageService _storageService = Get.find<StorageService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();

  Worker? _scanWorker;

  var itemFormKey = GlobalKey<FormState>();
  final String name = Get.arguments['name'];

  String mode = Get.arguments['mode'];

  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg = Get.arguments['posUploadName'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isAddingItem = false.obs;
  var isSaving = false.obs;

  var isDirty = false.obs;
  String _originalJson = '';

  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedInvoice = ''.obs;

  var itemFilter = 'All'.obs;

  var recentlyAddedItemCode = ''.obs;
  var recentlyAddedSerial = ''.obs;
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // Bottom Sheet State
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();
  final bsQtyController = TextEditingController(text: '6');
  final bsRackFocusNode = FocusNode();

  var isItemSheetOpen = false.obs;
  var isLoadingItemEdit = false.obs;
  var loadingForItemName = RxnString();
  var bsIsLoadingBatch = false.obs;
  var isValidatingBatch = false.obs;
  var bsMaxQty = 0.0.obs;
  var customerError = RxnString();
  var bsBatchError = RxnString();
  var bsIsBatchValid = false.obs;
  var batchInfoTooltip = RxnString();

  // Balance display state
  var bsBatchBalance = 0.0.obs;
  var bsRackBalance = 0.0.obs;
  var isLoadingBatchBalance = false.obs;
  var isLoadingRackBalance = false.obs;

  // Rack Validation State
  var bsIsRackValid = false.obs;
  var isValidatingRack = false.obs;
  var rackStockTooltip = RxnString();
  var rackStockMap = <String, double>{}.obs;
  var rackError = RxnString();

  var bsInvoiceSerialNo = RxnString();
  var editingItemName = RxnString();
  var isFormDirty = false.obs;
  var isSheetValid = false.obs;

  var bsItemVariantOf = RxnString();

  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';
  String? _initialSerial;

  // Warehouse State
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;
  var setWarehouse = RxnString();

  // Temp Item Data
  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModifiedBy = RxnString();
  var bsItemModified = RxnString();
  var bsItemIdx = RxnInt();
  var bsItemCustomVariantOf = RxnString();
  var bsItemGroup = RxnString();
  var bsItemImage = RxnString();
  var bsItemPackedQty = RxnDouble();
  var bsItemCompanyTotalStock = RxnDouble();
  var bsItemWarehouse = RxnString();

  String currentItemCode = '';
  String currentItemName = '';
  String currentScannedEan = '';

  Timer? _autoSubmitTimer;

  // Read-only lock helper.
  var bsIsBatchReadOnly = false.obs;

  // ---------------------------------------------------------------------------
  // Single source of truth for the qty ceiling.
  // ---------------------------------------------------------------------------
  double get effectiveMaxQty {
    double limit = 999999.0;
    if (bsMaxQty.value > 0 && bsMaxQty.value < limit) limit = bsMaxQty.value;
    if (bsBatchBalance.value > 0 && bsBatchBalance.value < limit) limit = bsBatchBalance.value;
    if (bsIsRackValid.value && bsRackBalance.value > 0 && bsRackBalance.value < limit) limit = bsRackBalance.value;
    log('[DN:effectiveMaxQty] bsMaxQty=${bsMaxQty.value} bsBatchBalance=${bsBatchBalance.value} '
        'bsIsRackValid=${bsIsRackValid.value} bsRackBalance=${bsRackBalance.value} → limit=$limit');
    return limit;
  }

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();

    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsRackController.addListener(validateSheet);
    ever(bsInvoiceSerialNo, (_) => validateSheet());
    ever(setWarehouse, (_) => _checkForChanges());

    ever(bsRackBalance, (_) => validateSheet());
    ever(bsIsRackValid, (_) => validateSheet());

    // Wire DataWedge stream — receives ALL scans whether sheet is open or not.
    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) scanBarcode(code);
    });

    _setupAutoSubmit();

    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDeliveryNote();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _autoSubmitTimer?.cancel();
    barcodeController.dispose();
    bsBatchController.dispose();
    bsRackController.dispose();
    bsQtyController.dispose();
    bsRackFocusNode.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void _setupAutoSubmit() {
    ever(isSheetValid, (bool valid) {
      _autoSubmitTimer?.cancel();
      if (valid && isItemSheetOpen.value && deliveryNote.value?.docstatus == 0) {
        if (_storageService.getAutoSubmitEnabled()) {
          final int delay = _storageService.getAutoSubmitDelay();
          log('[DN:_setupAutoSubmit] isSheetValid=$valid → scheduling auto-submit in ${delay}s');
          _autoSubmitTimer = Timer(Duration(seconds: delay), () async {
            log('[DN:_setupAutoSubmit] timer fired: isSheetValid=${isSheetValid.value} isItemSheetOpen=${isItemSheetOpen.value}');
            if (isSheetValid.value && isItemSheetOpen.value) {
              isAddingItem.value = true;
              await Future.delayed(const Duration(milliseconds: 500));
              await submitSheet();
              isAddingItem.value = false;
            }
          });
        }
      }
    });
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
      },
    );
  }

  void _checkForChanges() {
    if (deliveryNote.value == null) return;

    if (mode == 'new') {
      isDirty.value = true;
      return;
    }
    if (deliveryNote.value?.docstatus != 0) {
      isDirty.value = false;
      return;
    }

    final tempNote = DeliveryNote(
      name: deliveryNote.value!.name,
      customer: deliveryNote.value!.customer,
      grandTotal: deliveryNote.value!.grandTotal,
      postingDate: deliveryNote.value!.postingDate,
      modified: deliveryNote.value!.modified,
      creation: deliveryNote.value!.creation,
      status: deliveryNote.value!.status,
      currency: deliveryNote.value!.currency,
      items: deliveryNote.value!.items,
      poNo: deliveryNote.value!.poNo,
      totalQty: deliveryNote.value!.totalQty,
      docstatus: deliveryNote.value!.docstatus,
      setWarehouse: setWarehouse.value,
    );

    final currentJson = jsonEncode(tempNote.toJson());
    isDirty.value = currentJson != _originalJson;
  }

  void _updateOriginalState(DeliveryNote note) {
    _originalJson = jsonEncode(note.toJson());
    isDirty.value = false;
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      debugPrint('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    final now = DateTime.now();
    deliveryNote.value = DeliveryNote(
      name: 'New Delivery Note',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: now.toString().split(' ')[0],
      modified: '',
      creation: now.toString(),
      status: 'Draft',
      currency: 'AED',
      items: [],
      poNo: posUploadNameArg,
      totalQty: 0.0,
      docstatus: 0,
      setWarehouse: '',
    );
    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
    isDirty.value = true;
    _originalJson = '';
    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = note;
        setWarehouse.value = note.setWarehouse;
        _updateOriginalState(note);
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch delivery note');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load data: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchPosUpload(String posName) async {
    try {
      final response = await _posUploadProvider.getPosUpload(posName);
      if (response.statusCode == 200 && response.data['data'] != null) {
        posUpload.value = PosUpload.fromJson(response.data['data']);
      }
    } catch (e) {
      debugPrint('Failed to fetch linked POS Upload: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // STEP: Submit sheet → item written locally then saved
  // ---------------------------------------------------------------------------
  Future<void> submitSheet() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final rack = bsRackController.text;
    final batch = bsBatchController.text;
    final invoiceSerial = bsInvoiceSerialNo.value;

    log('[DN:submitSheet] ── SUBMIT ──────────────────────────────────────────');
    log('[DN:submitSheet] qty=$qty rack="$rack" batch="$batch" invoiceSerial=$invoiceSerial');
    log('[DN:submitSheet] editingItemName=${editingItemName.value} currentItemCode=$currentItemCode currentItemName=$currentItemName');
    log('[DN:submitSheet] isSheetValid=${isSheetValid.value} isFormDirty=${isFormDirty.value}');
    log('[DN:submitSheet] bsIsBatchValid=${bsIsBatchValid.value} bsIsRackValid=${bsIsRackValid.value}');
    log('[DN:submitSheet] bsBatchBalance=${bsBatchBalance.value} bsRackBalance=${bsRackBalance.value} bsMaxQty=${bsMaxQty.value}');

    if (editingItemName.value != null && editingItemName.value!.isNotEmpty) {
      log('[DN:submitSheet] → branch: UPDATE existing item "${editingItemName.value}"');
      _updateItemLocally(editingItemName.value!, qty, rack, batch, invoiceSerial);
    } else {
      log('[DN:submitSheet] → branch: ADD new item');
      _addItemLocally(currentItemCode, currentItemName, qty, rack, batch, invoiceSerial);
    }

    final ctx = Get.context;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();

    barcodeController.clear();
    _checkForChanges();

    await saveDeliveryNote();

    if (editingItemName.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        GlobalSnackbar.success(message: 'Item added/updated.');
      });
    }
  }

  // ---------------------------------------------------------------------------
  // STEP: Update an existing item row locally
  // ---------------------------------------------------------------------------
  void _updateItemLocally(String itemNameID, double qty, String rack, String? batchNo, String? invoiceSerial) {
    log('[DN:_updateItemLocally] itemNameID=$itemNameID qty=$qty rack="$rack" batchNo=$batchNo invoiceSerial=$invoiceSerial');
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final index = currentItems.indexWhere((item) => item.name == itemNameID);
    log('[DN:_updateItemLocally] found at index=$index (total items=${currentItems.length})');
    if (index != -1) {
      final existingItem = currentItems[index];
      log('[DN:_updateItemLocally] existing: itemCode=${existingItem.itemCode} qty=${existingItem.qty} batchNo=${existingItem.batchNo} rack=${existingItem.rack}');
      currentItems[index] = existingItem.copyWith(
        qty: qty,
        rack: rack,
        batchNo: batchNo,
        customInvoiceSerialNumber: invoiceSerial,
      );
      log('[DN:_updateItemLocally] ✅ updated row: qty=$qty rack="$rack" batchNo=$batchNo');
      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      _triggerItemFeedback(existingItem.itemCode, invoiceSerial ?? '0');
    } else {
      log('[DN:_updateItemLocally] ❌ item NOT FOUND in list — no update performed');
    }
  }

  // ---------------------------------------------------------------------------
  // STEP: Add a new item row locally
  // ---------------------------------------------------------------------------
  void _addItemLocally(String itemCode, String itemName, double qty, String rack, String? batchNo, String? invoiceSerial) {
    log('[DN:_addItemLocally] itemCode=$itemCode qty=$qty rack="$rack" batchNo=$batchNo invoiceSerial=$invoiceSerial');
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    final serial = invoiceSerial ?? '0';
    log('[DN:_addItemLocally] serial=$serial  existing items count=${currentItems.length}');

    final existingIndex = currentItems.indexWhere((item) =>
        item.itemCode == itemCode &&
        (item.batchNo ?? '') == (batchNo ?? '') &&
        (item.rack ?? '') == rack &&
        (item.customInvoiceSerialNumber ?? '0') == serial);

    log('[DN:_addItemLocally] duplicate check → existingIndex=$existingIndex');

    if (existingIndex != -1) {
      final existing = currentItems[existingIndex];
      final newQty = existing.qty + qty;
      log('[DN:_addItemLocally] ♻️ merging: old qty=${existing.qty} + $qty = $newQty');
      currentItems[existingIndex] = existing.copyWith(qty: newQty);
      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      _triggerItemFeedback(itemCode, serial);
    } else {
      final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      log('[DN:_addItemLocally] ✅ adding new row: tempId=$tempId itemCode=$itemCode qty=$qty rack="$rack" batchNo=$batchNo serial=$serial');
      final newItem = DeliveryNoteItem(
        name: tempId,
        itemCode: itemCode,
        qty: qty,
        rate: 0.0,
        rack: rack,
        batchNo: batchNo,
        customInvoiceSerialNumber: serial,
        itemName: itemName,
        creation: DateTime.now().toString(),
      );
      currentItems.add(newItem);
      deliveryNote.update((val) {
        val?.items.assignAll(currentItems);
      });
      log('[DN:_addItemLocally] deliveryNote items count after add=${deliveryNote.value?.items.length}');
      _triggerItemFeedback(itemCode, serial);
    }
  }

  Future<void> confirmAndDeleteItem(DeliveryNoteItem item) async {
    GlobalDialog.showConfirmation(
      title: 'Delete Item?',
      message: 'Are you sure you want to remove ${item.itemCode} from this note?',
      onConfirm: () => _deleteItemLocally(item),
    );
  }

  void _deleteItemLocally(DeliveryNoteItem item) {
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.remove(item);
    deliveryNote.update((val) {
      val?.items.assignAll(currentItems);
    });
    _checkForChanges();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalSnackbar.success(message: 'Item removed');
    });
  }

  Future<void> saveDeliveryNote() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    isSaving.value = true;
    customerError.value = null;

    try {
      final String docName = deliveryNote.value?.name ?? '';
      final bool isNew = docName == 'New Delivery Note' || docName.isEmpty;
      log('[DN:saveDeliveryNote] docName="$docName" isNew=$isNew');

      final Map<String, dynamic> data = deliveryNote.value!.toJson();
      data['set_warehouse'] = setWarehouse.value;

      if (!isNew && deliveryNote.value?.modified != null) {
        data['modified'] = deliveryNote.value?.modified;
      }

      if (isNew) {
        data['customer'] = deliveryNote.value!.customer;
        data['posting_date'] = deliveryNote.value!.postingDate;
        if (deliveryNote.value!.poNo != null) data['po_no'] = deliveryNote.value!.poNo;
        data['docstatus'] = 0;
      }

      final response = isNew
          ? await _apiProvider.createDocument('Delivery Note', data)
          : await _apiProvider.updateDocument('Delivery Note', docName, data);

      log('[DN:saveDeliveryNote] API response status=${response.statusCode}');

      if (response.statusCode == 200 && response.data['data'] != null) {
        final savedNote = DeliveryNote.fromJson(response.data['data']);
        log('[DN:saveDeliveryNote] ✅ saved: name=${savedNote.name} items=${savedNote.items.length}');
        deliveryNote.value = savedNote;
        _updateOriginalState(savedNote);
        if (isNew) mode = 'edit';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          GlobalSnackbar.success(message: 'Delivery Note Saved');
        });
      } else {
        log('[DN:saveDeliveryNote] ❌ failed: ${response.data}');
        GlobalSnackbar.error(message: 'Failed to save: ${response.data['exception'] ?? 'Unknown error'}');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      final errorMsg = e.response?.data.toString() ?? e.message ?? '';
      log('[DN:saveDeliveryNote] ❌ DioException: $errorMsg');
      if (errorMsg.contains('Customer') && errorMsg.contains('not found')) {
        customerError.value = 'Customer not found in the system';
      }
      GlobalSnackbar.error(message: 'Save failed: ${e.message}');
    } catch (e) {
      final errorMsg = e.toString();
      log('[DN:saveDeliveryNote] ❌ Exception: $errorMsg');
      if (errorMsg.contains('Customer') && errorMsg.contains('not found')) {
        customerError.value = 'Customer not found in the system';
      }
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  void _triggerItemFeedback(String itemCode, String serial) {
    recentlyAddedItemCode.value = itemCode;
    recentlyAddedSerial.value = serial;

    if (serial != '0' && serial.isNotEmpty) {
      expandedInvoice.value = serial;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final item = deliveryNote.value?.items.firstWhereOrNull(
            (i) => i.itemCode == itemCode && (i.customInvoiceSerialNumber ?? '0') == serial);

        if (item != null && item.name != null) {
          final key = itemKeys[item.name];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
          }
        }
      });
    });

    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemCode.value = '';
      recentlyAddedSerial.value = '';
    });
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    if (deliveryNote.value == null || deliveryNote.value!.items.isEmpty) return {};
    return groupBy(deliveryNote.value!.items,
        (DeliveryNoteItem item) => item.customInvoiceSerialNumber ?? '0');
  }

  int get allCount => posUpload.value?.items.length ?? 0;

  int get completedCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      return dnItems.fold(0.0, (sum, item) => sum + item.qty) >= posItem.quantity;
    }).length;
  }

  int get pendingCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      return dnItems.fold(0.0, (sum, item) => sum + item.qty) < posItem.quantity;
    }).length;
  }

  void setFilter(String filter) {
    itemFilter.value = filter;
  }

  List<String> get bsAvailableInvoiceSerialNos {
    if (posUpload.value == null) return [];
    return posUpload.value!.items.map((item) => item.idx.toString()).toList();
  }

  // ---------------------------------------------------------------------------
  // STEP: Validate sheet state — called after every field change
  // ---------------------------------------------------------------------------
  void validateSheet() {
    bool valid = true;
    rackError.value = null;

    final qty = double.tryParse(bsQtyController.text) ?? 0;
    final max = effectiveMaxQty;

    log('[DN:validateSheet] ── CHECK ────────────────────────────────────────');
    log('[DN:validateSheet] qty=$qty max=$max');
    log('[DN:validateSheet] batch="${bsBatchController.text}" bsIsBatchValid=${bsIsBatchValid.value} bsIsBatchReadOnly=${bsIsBatchReadOnly.value}');
    log('[DN:validateSheet] rack="${bsRackController.text}" bsIsRackValid=${bsIsRackValid.value}');
    log('[DN:validateSheet] invoiceSerial=${bsInvoiceSerialNo.value} availableSerials=${bsAvailableInvoiceSerialNos}');
    log('[DN:validateSheet] editingItemName=${editingItemName.value}');

    if (qty <= 0) {
      log('[DN:validateSheet] ✗ qty<=0');
      valid = false;
    }

    if (max < 999999.0 && qty > max) {
      log('[DN:validateSheet] ✗ qty=$qty exceeds max=$max');
      valid = false;
    }

    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) {
      log('[DN:validateSheet] ✗ batch field non-empty but bsIsBatchValid=false');
      valid = false;
    }

    if (bsRackController.text.isNotEmpty && !bsIsRackValid.value) {
      log('[DN:validateSheet] ✗ rack field non-empty but bsIsRackValid=false');
      valid = false;
    }

    final selectedRack = bsRackController.text;
    if (selectedRack.isNotEmpty && rackStockMap.isNotEmpty) {
      final availableInRack = rackStockMap[selectedRack] ?? 0.0;
      log('[DN:validateSheet] rack stock check: availableInRack[$selectedRack]=$availableInRack');
      if (availableInRack > 0 && qty > availableInRack) {
        valid = false;
        rackError.value = 'Only $availableInRack available in $selectedRack';
        log('[DN:validateSheet] ✗ qty=$qty exceeds rack stock=$availableInRack');
      }
    }

    if (bsInvoiceSerialNo.value == null || bsInvoiceSerialNo.value!.isEmpty) {
      if (bsAvailableInvoiceSerialNos.isNotEmpty) {
        log('[DN:validateSheet] ✗ invoiceSerial not set but posUpload has serials');
        valid = false;
      }
    }

    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsInvoiceSerialNo.value != _initialSerial) dirty = true;
    isFormDirty.value = dirty;

    if (editingItemName.value != null && !dirty) {
      log('[DN:validateSheet] ✗ edit mode but form not dirty');
      valid = false;
    }

    log('[DN:validateSheet] → isSheetValid=$valid dirty=$dirty');
    isSheetValid.value = valid;
  }

  // ---------------------------------------------------------------------------
  // STEP: initBottomSheet — seeds all sheet state before opening
  // ---------------------------------------------------------------------------
  void initBottomSheet(String itemCode, String itemName, String? batchNo, double maxQty,
      {DeliveryNoteItem? editingItem}) {
    log('[DN:initBottomSheet] ── INIT ─────────────────────────────────────────');
    log('[DN:initBottomSheet] itemCode=$itemCode itemName="$itemName" batchNo=$batchNo maxQty=$maxQty editing=${editingItem != null}');

    itemFormKey = GlobalKey<FormState>();
    currentItemCode = itemCode;
    currentItemName = itemName;
    bsItemOwner.value = null;
    bsItemCreation.value = null;
    bsItemModifiedBy.value = null;
    bsItemModified.value = null;
    bsItemIdx.value = null;
    bsItemCustomVariantOf.value = null;
    bsItemGroup.value = null;
    bsItemImage.value = null;
    bsItemPackedQty.value = null;
    bsItemCompanyTotalStock.value = null;
    bsItemVariantOf.value = null;
    isFormDirty.value = false;
    rackStockTooltip.value = null;
    rackStockMap.clear();
    rackError.value = null;
    bsBatchError.value = null;

    bsBatchBalance.value = 0.0;
    bsRackBalance.value = 0.0;
    isLoadingBatchBalance.value = false;
    isLoadingRackBalance.value = false;

    if (editingItem != null) {
      log('[DN:initBottomSheet] → EDIT branch: batchNo=${editingItem.batchNo} rack=${editingItem.rack} qty=${editingItem.qty} serial=${editingItem.customInvoiceSerialNumber}');
      bsItemOwner.value = editingItem.owner;
      bsItemCreation.value = editingItem.creation;
      bsItemModified.value = editingItem.modified;
      bsItemModifiedBy.value = editingItem.modifiedBy;
      bsItemVariantOf.value = editingItem.customVariantOf;

      editingItemName.value = editingItem.name;
      bsBatchController.text = editingItem.batchNo ?? '';
      bsRackController.text = editingItem.rack ?? '';
      bsQtyController.text = editingItem.qty.toStringAsFixed(0);
      bsInvoiceSerialNo.value = editingItem.customInvoiceSerialNumber;

      _initialBatch = editingItem.batchNo ?? '';
      _initialRack = editingItem.rack ?? '';
      _initialQty = editingItem.qty.toStringAsFixed(0);
      _initialSerial = editingItem.customInvoiceSerialNumber;

      bsIsBatchValid.value = (editingItem.batchNo != null && editingItem.batchNo!.isNotEmpty);
      bsIsRackValid.value = (editingItem.rack != null && editingItem.rack!.isNotEmpty);

      bsMaxQty.value = maxQty;
      log('[DN:initBottomSheet] EDIT seeds: bsIsBatchValid=${bsIsBatchValid.value} bsIsRackValid=${bsIsRackValid.value} bsMaxQty=$maxQty');
    } else {
      log('[DN:initBottomSheet] → NEW branch: resetting all flags');
      bsIsBatchReadOnly.value = false;
      bsIsBatchValid.value = false;

      editingItemName.value = null;
      bsBatchController.text = batchNo ?? '';
      bsRackController.clear();
      bsQtyController.text = '6';

      _initialBatch = batchNo ?? '';
      _initialRack = '';
      _initialQty = '6';

      bsMaxQty.value = maxQty;
      bsIsRackValid.value = false;

      bsInvoiceSerialNo.value = null;
      _initialSerial = null;

      if (batchNo != null && batchNo.isNotEmpty && maxQty > 0) {
        log('[DN:initBottomSheet] → batchNo+maxQty present → locking field immediately: batchNo=$batchNo maxQty=$maxQty');
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        bsBatchBalance.value = maxQty;
      } else if (batchNo != null && batchNo.isNotEmpty) {
        log('[DN:initBottomSheet] → batchNo present but maxQty=0 → scheduling validateAndFetchBatch("$batchNo")');
        Future.microtask(() => validateAndFetchBatch(batchNo));
      } else {
        log('[DN:initBottomSheet] → no batch/maxQty → field unlocked (batchNo=$batchNo maxQty=$maxQty)');
        bsBatchBalance.value = 0.0;
      }
    }

    log('[DN:initBottomSheet] state after seeding: bsBatchController="${bsBatchController.text}" bsRackController="${bsRackController.text}" bsQtyController="${bsQtyController.text}"');
    log('[DN:initBottomSheet] bsIsBatchValid=${bsIsBatchValid.value} bsIsBatchReadOnly=${bsIsBatchReadOnly.value} bsIsRackValid=${bsIsRackValid.value}');
    log('[DN:initBottomSheet] invoiceSerial=${bsInvoiceSerialNo.value} setWarehouse=${setWarehouse.value} bsItemWarehouse=${bsItemWarehouse.value}');

    validateSheet();
    _fetchAllRackStocks();

    bsIsLoadingBatch.value = false;
    isValidatingRack.value = false;
    isValidatingBatch.value = false;
    isItemSheetOpen.value = true;
  }

  // ---------------------------------------------------------------------------
  // STEP: Fetch all rack stocks for current item+warehouse+batch
  // ---------------------------------------------------------------------------
  Future<void> _fetchAllRackStocks() async {
    final warehouse = bsItemWarehouse.value ?? setWarehouse.value;
    log('[DN:_fetchAllRackStocks] itemCode=$currentItemCode warehouse=$warehouse batch="${bsBatchController.text}"');
    if (warehouse == null || warehouse.isEmpty) {
      log('[DN:_fetchAllRackStocks] ⚠️ warehouse is null/empty — skipping');
      return;
    }

    try {
      final response = await _apiProvider.getStockBalance(
        itemCode: currentItemCode,
        warehouse: warehouse,
        batchNo: bsBatchController.text.isNotEmpty ? bsBatchController.text : null,
      );

      log('[DN:_fetchAllRackStocks] API status=${response.statusCode}');

      if (response.statusCode == 200 && response.data['message'] != null) {
        final result = response.data['message']['result'];
        if (result is List && result.isNotEmpty) {
          final Map<String, double> tempMap = {};
          final List<String> tooltipLines = [];

          for (int i = 0; i < result.length - 1; i++) {
            final row = result[i];
            final String? r = row['rack'];
            final double qty = (row['bal_qty'] as num?)?.toDouble() ?? 0.0;

            if (r != null && r.isNotEmpty && qty > 0) {
              tempMap[r] = qty;
              tooltipLines.add('$r: $qty');
            }
          }

          log('[DN:_fetchAllRackStocks] rack map: $tempMap');
          rackStockMap.assignAll(tempMap);
          rackStockTooltip.value =
              tooltipLines.isNotEmpty ? tooltipLines.join('\n') : 'No stock in racks';

          if (bsIsRackValid.value && bsRackController.text.isNotEmpty) {
            bsRackBalance.value = tempMap[bsRackController.text] ?? 0.0;
            log('[DN:_fetchAllRackStocks] updated bsRackBalance=${bsRackBalance.value} for rack=${bsRackController.text}');
          }
        } else {
          log('[DN:_fetchAllRackStocks] result is empty or not a List');
        }
      } else {
        log('[DN:_fetchAllRackStocks] ⚠️ unexpected response: ${response.data}');
      }
    } catch (e) {
      log('[DN:_fetchAllRackStocks] ❌ Exception: $e');
      debugPrint('Error fetching rack stocks: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // STEP: Validate batch + fetch balance
  // ---------------------------------------------------------------------------
  Future<void> validateAndFetchBatch(String batchNo) async {
    log('[DN:validateAndFetchBatch] ── BATCH ────────────────────────────────────');
    log('[DN:validateAndFetchBatch] batchNo=$batchNo currentItemCode=$currentItemCode currentScannedEan=$currentScannedEan');
    log('[DN:validateAndFetchBatch] setWarehouse=${setWarehouse.value} bsItemWarehouse=${bsItemWarehouse.value}');
    if (batchNo.isEmpty) {
      log('[DN:validateAndFetchBatch] EARLY EXIT: batchNo is empty');
      return;
    }
    isValidatingBatch.value = true;
    isLoadingBatchBalance.value = true;
    bsBatchError.value = null;
    batchInfoTooltip.value = null;
    bsIsBatchValid.value = false;
    bsIsBatchReadOnly.value = false;

    try {
      final batchResponse = await _apiProvider.getDocumentList(
        'Batch',
        filters: {'name': batchNo, 'item': currentItemCode},
        fields: ['name', 'custom_packaging_qty'],
      );

      log('[DN:validateAndFetchBatch] Batch list response: status=${batchResponse.statusCode} data=${batchResponse.data['data']}');

      if (batchResponse.data['data'] == null ||
          (batchResponse.data['data'] as List).isEmpty) {
        log('[DN:validateAndFetchBatch] ❌ Batch NOT FOUND for name=$batchNo item=$currentItemCode → throwing');
        throw Exception('Batch not found');
      }

      final batchData = batchResponse.data['data'][0];
      final double pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
      log('[DN:validateAndFetchBatch] pkgQty=$pkgQty → ${pkgQty > 0 ? "overriding qty" : "keeping current qty"}');
      if (pkgQty > 0) {
        bsQtyController.text =
            pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
      }

      await _fetchAllRackStocks();

      String? determinedWarehouse = setWarehouse.value;
      if (bsRackController.text.isNotEmpty) {
        log('[DN:validateAndFetchBatch] rack field non-empty ("${bsRackController.text}") → looking up warehouse from rack');
        try {
          final rackRes = await _apiProvider.getDocument('Rack', bsRackController.text);
          if (rackRes.statusCode == 200 && rackRes.data['data'] != null) {
            determinedWarehouse = rackRes.data['data']['warehouse'] ?? determinedWarehouse;
            log('[DN:validateAndFetchBatch] warehouse from rack: $determinedWarehouse');
          }
        } catch (_) {}
      }

      log('[DN:validateAndFetchBatch] calling getBatchWiseBalance: itemCode=$currentItemCode batch=$batchNo warehouse=$determinedWarehouse');

      final balanceResponse = await _apiProvider.getBatchWiseBalance(
        currentItemCode,
        batchNo,
        warehouse: determinedWarehouse,
      );

      log('[DN:validateAndFetchBatch] balance response status=${balanceResponse.statusCode}');
      log('[DN:validateAndFetchBatch] balance message=${balanceResponse.data['message']}');

      double fetchedBatchQty = 0.0;
      if (balanceResponse.statusCode == 200 &&
          balanceResponse.data['message'] != null) {
        final message = balanceResponse.data['message'];
        final List<dynamic> result = message['result'] ?? [];
        log('[DN:validateAndFetchBatch] result rows=${result.length}');
        for (final row in result) {
          if (row is Map) {
            final dynamic val = row['balance_qty'] ?? row['bal_qty'] ?? row['qty_after_transaction'] ?? row['qty'];
            final double rowQty = (val as num?)?.toDouble() ?? 0.0;
            log('[DN:validateAndFetchBatch]   Map row val=$val → $rowQty');
            fetchedBatchQty += rowQty;
          } else if (row is List) {
            if (row.isNotEmpty && row[0] is String) {
              log('[DN:validateAndFetchBatch]   skipping header row: $row');
              continue;
            }
            final cols = message['columns'];
            if (cols is List) {
              int idx = -1;
              for (int i = 0; i < cols.length; i++) {
                final col = cols[i];
                if (col is Map) {
                  final label = (col['label'] ?? '').toString().toLowerCase();
                  final fieldname = (col['fieldname'] ?? '').toString().toLowerCase();
                  if (label.contains('balance qty') ||
                      (fieldname.contains('balance') && fieldname.contains('qty'))) {
                    idx = i;
                    break;
                  }
                }
              }
              if (idx >= 0 && idx < row.length) {
                final double rowQty = (row[idx] as num?)?.toDouble() ?? 0.0;
                log('[DN:validateAndFetchBatch]   List row col[$idx]=$rowQty');
                fetchedBatchQty += rowQty;
              } else {
                log('[DN:validateAndFetchBatch]   ⚠️ balance qty column not found in cols');
              }
            }
          }
        }
      }

      log('[DN:validateAndFetchBatch] fetchedBatchQty=$fetchedBatchQty');

      bsMaxQty.value = fetchedBatchQty;
      bsBatchBalance.value = fetchedBatchQty;

      final sb = StringBuffer();
      sb.writeln('Batch Stock: $fetchedBatchQty');
      if (rackStockTooltip.value != null) {
        sb.writeln('\nRack Availability:');
        sb.write(rackStockTooltip.value);
      }
      batchInfoTooltip.value = sb.toString().trim();

      if (fetchedBatchQty > 0) {
        log('[DN:validateAndFetchBatch] ✅ batch valid, locking field, focusing rack');
        bsIsBatchValid.value = true;
        bsIsBatchReadOnly.value = true;
        bsBatchError.value = null;
        bsRackFocusNode.requestFocus();
      } else {
        log('[DN:validateAndFetchBatch] ⚠️ fetchedBatchQty=0 → no stock error');
        bsBatchError.value = 'Batch has no stock in this warehouse';
      }

      final double enteredQty = double.tryParse(bsQtyController.text) ?? 0.0;
      log('[DN:validateAndFetchBatch] qty check: enteredQty=$enteredQty fetchedBatchQty=$fetchedBatchQty');
      if (fetchedBatchQty > 0 && enteredQty > fetchedBatchQty) {
        bsBatchError.value =
            'Qty ($enteredQty) exceeds batch balance (${fetchedBatchQty.toStringAsFixed(0)})';
        log('[DN:validateAndFetchBatch] ⚠️ qty exceeds balance → ${bsBatchError.value}');
      }
    } catch (e) {
      log('[DN:validateAndFetchBatch] ❌ EXCEPTION: $e');
      bsBatchError.value = 'Invalid Batch';
      bsMaxQty.value = 0.0;
      bsBatchBalance.value = 0.0;
      bsIsBatchValid.value = false;
      bsIsBatchReadOnly.value = false;
      GlobalSnackbar.error(message: 'Batch validation failed');
    } finally {
      isValidatingBatch.value = false;
      isLoadingBatchBalance.value = false;
      log('[DN:validateAndFetchBatch] finally: bsIsBatchValid=${bsIsBatchValid.value} bsBatchBalance=${bsBatchBalance.value}');
      validateSheet();
    }
  }

  void resetBatchValidation() {
    log('[DN:resetBatchValidation] resetting batch state');
    bsIsBatchValid.value = false;
    bsIsBatchReadOnly.value = false;
    bsBatchBalance.value = 0.0;
    bsBatchError.value = null;
    validateSheet();
  }

  // ---------------------------------------------------------------------------
  // STEP: Validate rack
  // ---------------------------------------------------------------------------
  Future<void> validateRack(String rack) async {
    log('[DN:validateRack] ── RACK ──────────────────────────────────────────────');
    log('[DN:validateRack] rack="$rack" currentItemCode=$currentItemCode setWarehouse=${setWarehouse.value}');
    if (rack.isEmpty) {
      log('[DN:validateRack] rack empty → clearing state');
      bsIsRackValid.value = false;
      bsItemWarehouse.value = null;
      bsRackBalance.value = 0.0;
      validateSheet();
      return;
    }

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        bsItemWarehouse.value = '${parts[1]}-${parts[2]} - ${parts[0]}';
        log('[DN:validateRack] derived warehouse from rack name: ${bsItemWarehouse.value}');
      }
    }

    isValidatingRack.value = true;
    isLoadingRackBalance.value = true;
    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      log('[DN:validateRack] API response status=${response.statusCode} data=${response.data['data']}');
      if (response.statusCode == 200 && response.data['data'] != null) {
        bsIsRackValid.value = true;

        if (response.data['data']['warehouse'] != null) {
          bsItemWarehouse.value = response.data['data']['warehouse'];
          log('[DN:validateRack] warehouse from API: ${bsItemWarehouse.value}');
        }

        validateSheet();
        await _fetchAllRackStocks();

        bsRackBalance.value = rackStockMap[rack] ?? 0.0;
        log('[DN:validateRack] ✅ rack valid, balance=${bsRackBalance.value}  rackStockMap keys=${rackStockMap.keys.toList()}');
      } else {
        log('[DN:validateRack] ❌ rack not found in API response');
        bsIsRackValid.value = false;
        bsRackBalance.value = 0.0;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      log('[DN:validateRack] ❌ EXCEPTION: $e');
      bsIsRackValid.value = false;
      bsRackBalance.value = 0.0;
      GlobalSnackbar.error(message: 'Validation failed: $e');
    } finally {
      isValidatingRack.value = false;
      isLoadingRackBalance.value = false;
      log('[DN:validateRack] finally: bsIsRackValid=${bsIsRackValid.value} bsRackBalance=${bsRackBalance.value}');
      validateSheet();
    }
  }

  void resetRackValidation() {
    log('[DN:resetRackValidation] resetting rack state');
    bsIsRackValid.value = false;
    bsRackBalance.value = 0.0;
    validateSheet();
  }

  void adjustSheetQty(double amount) {
    double currentQty = double.tryParse(bsQtyController.text) ?? 0;
    double newQty = currentQty + amount;
    if (newQty < 0) newQty = 0;
    final limit = effectiveMaxQty;
    if (limit < 999999.0 && newQty > limit) newQty = limit;
    log('[DN:adjustSheetQty] amount=$amount old=$currentQty new=$newQty limit=$limit');
    bsQtyController.text = newQty.toStringAsFixed(0);
    validateSheet();
  }

  // ---------------------------------------------------------------------------
  // STEP: Open edit sheet for existing item
  // ---------------------------------------------------------------------------
  Future<void> editItem(DeliveryNoteItem item) async {
    log('[DN:editItem] ── EDIT ──────────────────────────────────────────────────');
    log('[DN:editItem] itemCode=${item.itemCode} name=${item.name} batchNo=${item.batchNo} rack=${item.rack} qty=${item.qty}');
    loadingForItemName.value = item.name;
    isLoadingItemEdit.value = true;
    double fetchedQty = 0.0;
    bsIsLoadingBatch.value = true;
    isLoadingBatchBalance.value = true;
    isLoadingRackBalance.value = true;

    if (item.batchNo != null && item.batchNo!.contains('-')) {
      currentScannedEan = item.batchNo!.split('-').first;
    } else {
      currentScannedEan = '';
    }
    log('[DN:editItem] derived currentScannedEan="$currentScannedEan" from batchNo=${item.batchNo}');

    try {
      if (item.batchNo != null) {
        String? targetWh = setWarehouse.value;
        log('[DN:editItem] batchNo present → fetching balance. initial targetWh=$targetWh');
        if (item.rack != null && item.rack!.isNotEmpty) {
          log('[DN:editItem] rack present ("${item.rack}") → deriving warehouse from rack API');
          try {
            final rackRes = await _apiProvider.getDocument('Rack', item.rack!);
            if (rackRes.statusCode == 200 && rackRes.data['data'] != null) {
              targetWh = rackRes.data['data']['warehouse'];
              log('[DN:editItem] targetWh from rack API: $targetWh');
            }
          } catch (_) {
            log('[DN:editItem] ⚠️ rack API failed, keeping targetWh=$targetWh');
          }
        }

        log('[DN:editItem] calling getBatchWiseBalance: itemCode=${item.itemCode} batchNo=${item.batchNo} warehouse=$targetWh');
        final balanceResponse = await _apiProvider.getBatchWiseBalance(
          item.itemCode,
          item.batchNo!,
          warehouse: targetWh,
        );
        log('[DN:editItem] balance response status=${balanceResponse.statusCode} message=${balanceResponse.data['message']}');

        if (balanceResponse.statusCode == 200 &&
            balanceResponse.data['message'] != null) {
          final message = balanceResponse.data['message'];
          final List<dynamic> result = message['result'] ?? [];
          log('[DN:editItem] result rows=${result.length}');
          for (final row in result) {
            if (row is Map) {
              final dynamic val = row['balance_qty'] ?? row['bal_qty'] ?? row['qty_after_transaction'] ?? row['qty'];
              final double rowQty = (val as num?)?.toDouble() ?? 0.0;
              log('[DN:editItem]   Map row val=$val → $rowQty');
              fetchedQty += rowQty;
            } else if (row is List) {
              if (row.isNotEmpty && row[0] is String) {
                log('[DN:editItem]   skipping header row');
                continue;
              }
              final cols = message['columns'];
              if (cols is List) {
                int idx = -1;
                for (int i = 0; i < cols.length; i++) {
                  final col = cols[i];
                  if (col is Map) {
                    final label = (col['label'] ?? '').toString().toLowerCase();
                    final fieldname = (col['fieldname'] ?? '').toString().toLowerCase();
                    if (label.contains('balance qty') ||
                        (fieldname.contains('balance') && fieldname.contains('qty'))) {
                      idx = i;
                      break;
                    }
                  }
                }
                if (idx >= 0 && idx < row.length) {
                  final double rowQty = (row[idx] as num?)?.toDouble() ?? 0.0;
                  log('[DN:editItem]   List row col[$idx]=$rowQty');
                  fetchedQty += rowQty;
                } else {
                  log('[DN:editItem]   ⚠️ balance qty column not found');
                }
              }
            }
          }
        }
        log('[DN:editItem] fetchedQty=$fetchedQty');
      } else {
        log('[DN:editItem] batchNo is null → skipping balance fetch, fetchedQty stays 0');
      }
    } catch (e) {
      log('[DN:editItem] ❌ EXCEPTION during balance fetch: $e — defaulting fetchedQty=999');
      fetchedQty = 999;
    } finally {
      bsIsLoadingBatch.value = false;
      isLoadingBatchBalance.value = false;
      isLoadingRackBalance.value = false;
      isLoadingItemEdit.value = false;
      loadingForItemName.value = null;
    }

    log('[DN:editItem] calling initBottomSheet with fetchedQty=$fetchedQty');
    initBottomSheet(item.itemCode, item.itemName ?? '', item.batchNo, fetchedQty,
        editingItem: item);

    bsBatchBalance.value = fetchedQty;
    if (item.rack != null && item.rack!.isNotEmpty) {
      bsRackBalance.value = rackStockMap[item.rack] ?? 0.0;
      log('[DN:editItem] bsRackBalance set to ${bsRackBalance.value} for rack=${item.rack}');
    }

    log('[DN:editItem] opening bottomSheet');
    await Get.bottomSheet(
      _FadeSlideSheet(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return DeliveryNoteItemBottomSheet(scrollController: scrollController);
          },
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enterBottomSheetDuration: const Duration(milliseconds: 350),
      exitBottomSheetDuration: const Duration(milliseconds: 250),
    );

    log('[DN:editItem] bottomSheet closed → resetting isItemSheetOpen + editingItemName');
    isItemSheetOpen.value = false;
    editingItemName.value = null;
  }

  bool _validateHeaderBeforeScan() {
    if (deliveryNote.value == null) return false;
    if (deliveryNote.value!.customer.isEmpty) {
      GlobalSnackbar.error(message: 'Missing Customer: Please select a customer before scanning.');
      return false;
    }
    if (customerError.value != null) {
      GlobalSnackbar.error(message: 'Invalid Customer: ${customerError.value}');
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // STEP: Handle barcode scan (outside or inside sheet)
  // ---------------------------------------------------------------------------
  Future<void> scanBarcode(String barcode) async {
    log('[DN:scanBarcode] ── SCAN ────────────────────────────────────────────────');
    log('[DN:scanBarcode] barcode="$barcode" isItemSheetOpen=${isItemSheetOpen.value} isScanning=${isScanning.value}');
    if (barcode.isEmpty) return;
    if (checkStaleAndBlock()) return;
    if (!_validateHeaderBeforeScan()) {
      log('[DN:scanBarcode] ✋ blocked by _validateHeaderBeforeScan');
      return;
    }

    if (isItemSheetOpen.value) {
      barcodeController.clear();

      final String? contextEan = currentScannedEan.isNotEmpty ? currentScannedEan : null;
      log('[DN:scanBarcode] inside-sheet: contextEan=$contextEan currentItemCode=$currentItemCode');

      final result = await _scanService.processScan(barcode, contextItemCode: contextEan);
      log('[DN:scanBarcode] processScan → type=${result.type} batchNo=${result.batchNo} rackId=${result.rackId} rawCode=${result.rawCode} message=${result.message}');

      if (result.type == ScanType.rack && result.rackId != null) {
        log('[DN:scanBarcode] → RACK: unlocking then setting bsRackController="${result.rackId}"');
        resetRackValidation();
        bsRackController.text = result.rackId!;
        validateRack(result.rackId!);
      } else if (result.type == ScanType.batch && result.batchNo != null) {
        log('[DN:scanBarcode] → BATCH: unlocking then setting bsBatchController="${result.batchNo}"');
        resetBatchValidation();
        bsBatchController.text = result.batchNo!;
        validateAndFetchBatch(result.batchNo!);
      } else if (result.type == ScanType.item) {
        final fallbackBatch = result.batchNo ?? barcode.trim();
        log('[DN:scanBarcode] → ITEM fallback: unlocking then setting fallbackBatch=$fallbackBatch');
        resetBatchValidation();
        bsBatchController.text = fallbackBatch;
        validateAndFetchBatch(fallbackBatch);
      } else if (result.type == ScanType.error) {
        log('[DN:scanBarcode] → ERROR: contextEan=$contextEan message=${result.message}');
        if (contextEan == null) {
          GlobalSnackbar.error(message: 'Please scan the item EAN barcode first, then scan the batch suffix.');
        } else {
          GlobalSnackbar.error(message: result.message ?? 'Invalid Scan');
        }
      } else {
        log('[DN:scanBarcode] ⚠️ UNHANDLED type=${result.type}');
      }
      return;
    }

    log('[DN:scanBarcode] outside-sheet path');
    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);
      log('[DN:scanBarcode] outside processScan → type=${result.type} batchNo=${result.batchNo} itemCode=${result.itemData?.itemCode} rawCode=${result.rawCode}');

      if (result.isSuccess && result.itemData != null) {
        if (result.rawCode.contains('-') && !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-')[0];
        } else {
          currentScannedEan = result.rawCode;
        }
        log('[DN:scanBarcode] outside → currentScannedEan="$currentScannedEan"');

        final itemData = result.itemData!;
        double maxQty = 0.0;

        if (result.batchNo != null) {
          log('[DN:scanBarcode] outside → batchNo present, fetching balance for itemCode=${itemData.itemCode} batchNo=${result.batchNo} warehouse=${setWarehouse.value}');
          try {
            final balanceResponse = await _apiProvider.getBatchWiseBalance(
              itemData.itemCode,
              result.batchNo!,
              warehouse: setWarehouse.value,
            );
            log('[DN:scanBarcode] outside balance status=${balanceResponse.statusCode}');
            if (balanceResponse.statusCode == 200 &&
                balanceResponse.data['message']?['result'] != null) {
              final message = balanceResponse.data['message'];
              final list = message['result'] as List;
              for (final row in list) {
                if (row is Map) {
                  final dynamic val = row['balance_qty'] ?? row['bal_qty'] ?? row['qty_after_transaction'] ?? row['qty'];
                  maxQty += (val as num?)?.toDouble() ?? 0.0;
                } else if (row is List) {
                  if (row.isNotEmpty && row[0] is String) continue;
                  final cols = message['columns'];
                  if (cols is List) {
                    int idx = -1;
                    for (int i = 0; i < cols.length; i++) {
                      final col = cols[i];
                      if (col is Map) {
                        final label = (col['label'] ?? '').toString().toLowerCase();
                        final fieldname = (col['fieldname'] ?? '').toString().toLowerCase();
                        if (label.contains('balance qty') ||
                            (fieldname.contains('balance') && fieldname.contains('qty'))) {
                          idx = i;
                          break;
                        }
                      }
                    }
                    if (idx >= 0 && idx < row.length) {
                      maxQty += (row[idx] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                }
              }
            }
          } catch (_) {
            log('[DN:scanBarcode] outside ⚠️ balance fetch failed → maxQty=6');
            maxQty = 6.0;
          }
        }

        log('[DN:scanBarcode] outside → opening sheet: itemCode=${itemData.itemCode} batchNo=${result.batchNo} maxQty=$maxQty');
        isScanning.value = false;
        barcodeController.clear();

        initBottomSheet(itemData.itemCode, itemData.itemName, result.batchNo, maxQty);

        await Get.bottomSheet(
          _FadeSlideSheet(
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return DeliveryNoteItemBottomSheet(scrollController: scrollController);
              },
            ),
          ),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enterBottomSheetDuration: const Duration(milliseconds: 350),
          exitBottomSheetDuration: const Duration(milliseconds: 250),
        );

        isItemSheetOpen.value = false;
      } else if (result.type == ScanType.multiple && result.candidates != null) {
        log('[DN:scanBarcode] outside → multiple matches');
        GlobalSnackbar.warning(message: 'Multiple items found. Please search manually.');
      } else {
        log('[DN:scanBarcode] outside → no match: message=${result.message}');
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      log('[DN:scanBarcode] ❌ EXCEPTION outside: $e');
      GlobalSnackbar.error(message: 'Scan processing failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }
}

class _FadeSlideSheet extends StatelessWidget {
  final Widget child;
  const _FadeSlideSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
