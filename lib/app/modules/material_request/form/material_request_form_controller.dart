import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/shared/item_sheet/qty_field_delegate.dart';

class MaterialRequestFormController extends GetxController
    with OptimisticLockingMixin
    implements QtyFieldDelegate {
  final MaterialRequestProvider _provider =
      Get.find<MaterialRequestProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  final StorageService _storageService = Get.find<StorageService>();

  String name = Get.arguments['name'] ?? '';
  String mode = Get.arguments['mode'] ?? 'view';

  var isLoading = true.obs;
  var isSaving = false.obs;
  var isDirty = false.obs;
  var isScanning = false.obs;

  /// Drives the animated Save button state — identical to the pattern used
  /// in StockEntryFormController / SaveIconButton across all DocTypes.
  ///
  /// SaveResult has three values: idle | success | error.
  /// The in-flight spinner is driven by isSaving: true (not a SaveResult
  /// member), so saveResult stays idle during the API call and is set to
  /// success or error when the call completes.
  var saveResult = SaveResult.idle.obs;

  var materialRequest = Rx<MaterialRequest?>(null);

  // ── Header form fields ──────────────────────────────────────────────────
  final selectedType = 'Material Transfer'.obs;
  final scheduleDateController = TextEditingController();
  final transactionDateController = TextEditingController();
  final setWarehouseController = TextEditingController();

  final List<String> requestTypes = [
    'Purchase',
    'Material Transfer',
    'Material Issue',
    'Manufacture',
    'Customer Provided',
  ];

  // ── Warehouse data ─────────────────────────────────────────────────────────
  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  // ── Item Sheet State ─────────────────────────────────────────────────────
  final itemFormKey = GlobalKey<FormState>();

  @override
  final bsQtyController = TextEditingController();
  final bsWarehouseController = TextEditingController();
  final bsDateController = TextEditingController();

  var bsMaxQty = 0.0.obs;
  var bsItemVariantOf = RxnString();

  var isFormDirty = false.obs;
  var isSheetValid = false.obs;
  var isAddingItem = false.obs;

  String _initialQty = '';
  String _initialWh = '';

  var currentItemCode = '';
  var currentItemName = '';
  var currentItemNameKey = RxnString();
  var isItemSheetOpen = false.obs;

  final TextEditingController barcodeController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // ── QtyFieldDelegate ─────────────────────────────────────────────────────
  //
  // MR uses a lightweight validation model: qty > 0 is the only rule.
  // There is no batch ceiling, rack balance, or POS serial cap, so:
  //   • qtyInfoText    returns null  → QtyCapBadge is not rendered.
  //   • qtyInfoTooltip returns null  → badge tap does nothing.
  //   • qtyError       is always ''  → no inline error text shown.
  //   • isQtyValid     mirrors isSheetValid (the existing gate).
  //
  // validateSheet() already writes isSheetValid; isQtyValid is kept in sync
  // inside that method so SharedQtyField's Obx picks up the correct state.

  @override
  final RxBool isQtyValid = false.obs;

  @override
  final RxString qtyError = RxString('');

  @override
  String? get qtyInfoText => null;

  @override
  final RxnString qtyInfoTooltip = RxnString(null);

  // ── Persistent scan worker ──────────────────────────────────────────────────
  Worker? _scanWorker;

  bool get isEditable => (materialRequest.value?.docstatus ?? 1) == 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    bsQtyController.addListener(validateSheet);
    bsWarehouseController.addListener(validateSheet);
    fetchWarehouses();

    _scanWorker = ever(_dataWedgeService.scannedCode, _onRawScan);
    log('[MR:onInit] _scanWorker registered', name: 'MR');

    if (mode == 'new') {
      _initNewRequest();
    } else {
      fetchMaterialRequest();
    }
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    log('[MR:onClose] _scanWorker disposed', name: 'MR');
    scheduleDateController.dispose();
    transactionDateController.dispose();
    setWarehouseController.dispose();
    bsQtyController.dispose();
    bsDateController.dispose();
    bsWarehouseController.dispose();
    barcodeController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  @override
  Future<void> reloadDocument() async {
    await fetchMaterialRequest();
    GlobalSnackbar.success(message: 'Document reloaded successfully');
  }

  // ── Raw scan entry point (DataWedge hardware trigger) ─────────────────────

  void _onRawScan(String code) {
    log('[MR:_onRawScan] code="$code" route=${Get.currentRoute}', name: 'MR');
    if (code.isEmpty) return;
    if (Get.currentRoute != AppRoutes.MATERIAL_REQUEST_FORM) return;
    final clean = code.trim();
    barcodeController.text = clean;
    scanBarcode(clean);
  }

  // ── Warehouse ───────────────────────────────────────────────────────────────────

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList(
        'Warehouse',
        filters: {'is_group': 0},
        limit: 100,
      );
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  // ── Document init ──────────────────────────────────────────────────────────────

  void _initNewRequest() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    selectedType.value = 'Material Transfer';
    transactionDateController.text = dateStr;
    scheduleDateController.text = dateStr;
    setWarehouseController.clear();

    materialRequest.value = MaterialRequest(
      name: 'New Material Request',
      modified: dateStr,
      transactionDate: dateStr,
      scheduleDate: dateStr,
      status: 'Draft',
      docstatus: 0,
      materialRequestType: 'Material Transfer',
      items: [],
    );
    isLoading.value = false;
    isDirty.value = true;
  }

  Future<void> fetchMaterialRequest() async {
    isLoading.value = true;
    try {
      final response = await _provider.getMaterialRequest(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final entry = MaterialRequest.fromJson(response.data['data']);
        materialRequest.value = entry;

        selectedType.value = entry.materialRequestType;
        transactionDateController.text = entry.transactionDate;
        scheduleDateController.text = entry.scheduleDate;
        setWarehouseController.text = entry.setWarehouse ?? '';

        isDirty.value = false;
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch document');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Dirty / Navigation ───────────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) {
      isDirty.value = true;
    }
  }

  // ── Header field interactions ──────────────────────────────────────────────────

  void onTypeChanged(String? val) {
    if (val != null && val != selectedType.value) {
      selectedType.value = val;
      _markDirty();
    }
  }

  void onWarehouseChanged(String val) => _markDirty();

  void setDate(TextEditingController controller) async {
    if (materialRequest.value?.docstatus != 0) return;

    final DateTime? picked = await showDatePicker(
      context: Get.context!,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
      _markDirty();
    }
  }

  // ── Warehouse picker ────────────────────────────────────────────────────────────

  void showWarehousePicker({bool forItem = false}) {
    Get.bottomSheet(
      WarehousePickerSheet(
        warehouses: warehouses,
        isLoading: isFetchingWarehouses.value,
        onSelected: (wh) {
          if (forItem) {
            bsWarehouseController.text = wh;
            // validateSheet is called via bsWarehouseController listener
          } else {
            setWarehouseController.text = wh;
            onWarehouseChanged(wh);
          }
        },
      ),
      isScrollControlled: true,
    );
  }

  // ── Item default-warehouse lookup ──────────────────────────────────────────────
  //
  // Fetches Item DocType and extracts `default_warehouse` from the
  // `item_defaults` child-table row that matches the current session company.
  // Result is applied to [bsWarehouseController] only if the sheet is still
  // open (guard: isItemSheetOpen) so a fast dismiss never causes stale data.
  //
  // Priority chain:
  //   item_defaults[company == sessionCompany].default_warehouse
  //     → setWarehouseController.text (header-level fallback)
  //       → '' (leave blank)
  //
  // Called fire-and-forget after the sheet is opened; errors are silently
  // logged so they never interrupt the user workflow.
  void _prefillWarehouseFromItemDefaults(String itemCode) {
    _fetchItemDefaultWarehouse(itemCode).then((warehouse) {
      if (!isItemSheetOpen.value) return; // sheet was dismissed, skip
      if (warehouse != null && warehouse.isNotEmpty) {
        bsWarehouseController.text = warehouse;
        _initialWh = warehouse;
      }
      // If null/empty the existing value (setWarehouseController fallback
      // set synchronously in openItemSheet) is kept as-is.
    }).catchError((Object e) {
      log('[MR] _prefillWarehouseFromItemDefaults error: $e', name: 'MR');
    });
  }

  Future<String?> _fetchItemDefaultWarehouse(String itemCode) async {
    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode != 200) return null;

      final data = response.data['data'];
      if (data == null) return null;

      final List<dynamic> itemDefaults =
          (data['item_defaults'] as List<dynamic>?) ?? [];
      if (itemDefaults.isEmpty) return null;

      final String sessionCompany = _storageService.getCompany();

      // Prefer the row matching the current session company.
      Map<String, dynamic>? matchedRow;
      for (final entry in itemDefaults) {
        if (entry is Map<String, dynamic> &&
            entry['company'] == sessionCompany) {
          matchedRow = entry;
          break;
        }
      }

      // Fall back to first row if no company match (e.g. single-company setup).
      matchedRow ??= itemDefaults.first is Map<String, dynamic>
          ? itemDefaults.first as Map<String, dynamic>
          : null;

      final warehouse = matchedRow?['default_warehouse'] as String?;
      return (warehouse != null && warehouse.isNotEmpty) ? warehouse : null;
    } catch (e) {
      log('[MR] _fetchItemDefaultWarehouse error for "$itemCode": $e',
          name: 'MR');
      return null;
    }
  }

  // ── Item Sheet ───────────────────────────────────────────────────────────────────

  void openItemSheet({
    MaterialRequestItem? item,
    String? newCode,
    String? newName,
    String? variantOf,
  }) {
    bsQtyController.clear();
    bsDateController.text = scheduleDateController.text;
    bsWarehouseController.clear();
    bsMaxQty.value = 0;
    bsItemVariantOf.value = null;
    isFormDirty.value = false;
    isSheetValid.value = false;
    isQtyValid.value = false;
    qtyError.value = '';
    _initialQty = '';
    _initialWh = '';

    if (item != null) {
      // ── Edit mode: populate from existing item row; no lookup needed ──
      currentItemCode = item.itemCode;
      currentItemName = item.itemName ?? item.itemCode;
      currentItemNameKey.value = item.name;
      bsItemVariantOf.value = variantOf ?? item.variantOf;

      final qtyStr = item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toString();
      bsQtyController.text = qtyStr;
      bsWarehouseController.text = item.warehouse ?? '';

      _initialQty = qtyStr;
      _initialWh = item.warehouse ?? '';

      validateSheet();
    } else if (newCode != null && newCode.isNotEmpty) {
      // ── Add mode (item code known, e.g. barcode scan) ────────────────
      currentItemCode = newCode;
      currentItemName = newName ?? newCode;
      currentItemNameKey.value = null;
      bsItemVariantOf.value = variantOf;

      // Seed with header warehouse immediately so the field is never blank
      // while the async lookup runs.
      final headerWarehouse = setWarehouseController.text;
      bsWarehouseController.text = headerWarehouse;
      _initialWh = headerWarehouse;

      // Fire-and-forget: update warehouse once Item DocType is fetched.
      _prefillWarehouseFromItemDefaults(newCode);
    } else {
      // ── Add mode (no item code yet, manual entry) ────────────────────
      currentItemCode = '';
      currentItemName = '';
      currentItemNameKey.value = null;
      bsItemVariantOf.value = null;

      final headerWarehouse = setWarehouseController.text;
      bsWarehouseController.text = headerWarehouse;
      _initialWh = headerWarehouse;
    }

    isItemSheetOpen.value = true;
    showModalBottomSheet(
      context: Get.context!,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.90;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: MaterialRequestItemFormSheet(controller: this),
            ),
          ),
        );
      },
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      barcodeController.clear();
    });
  }

  // ── Sheet validation ───────────────────────────────────────────────────────────

  @override
  void validateSheet() {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    bool valid = qty > 0 && currentItemCode.isNotEmpty;

    bool dirty = false;
    if (bsQtyController.text != _initialQty) dirty = true;
    if (bsWarehouseController.text != _initialWh) dirty = true;
    isFormDirty.value = dirty;

    if (currentItemNameKey.value != null && !dirty) valid = false;

    isSheetValid.value = valid;
    // Keep QtyFieldDelegate sub-field in sync with sheet gate.
    isQtyValid.value = valid;
  }

  void adjustSheetQty(int delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = current + delta;
    if (newVal < 0) return;
    bsQtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    validateSheet();
  }

  // ── Save / Delete item ─────────────────────────────────────────────────────────────

  Future<void> saveItem() async {
    final qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0 || currentItemCode.isEmpty) return;

    isAddingItem.value = true;
    try {
      final currentItems = materialRequest.value?.items.toList() ?? [];

      if (currentItemNameKey.value != null) {
        final index = currentItems
            .indexWhere((i) => i.name == currentItemNameKey.value);
        if (index != -1) {
          final existing = currentItems[index];
          currentItems[index] = MaterialRequestItem(
            name: existing.name,
            itemCode: existing.itemCode,
            itemName: existing.itemName,
            qty: qty,
            receivedQty: existing.receivedQty,
            orderedQty: existing.orderedQty,
            actualQty: existing.actualQty,
            warehouse: bsWarehouseController.text,
            uom: existing.uom,
            description: existing.description,
            variantOf: existing.variantOf,
          );
        }
      } else {
        currentItems.add(MaterialRequestItem(
          name: 'local_${DateTime.now().millisecondsSinceEpoch}',
          itemCode: currentItemCode,
          itemName: currentItemName,
          qty: qty,
          warehouse: bsWarehouseController.text,
          description: currentItemName,
          variantOf: bsItemVariantOf.value,
        ));
      }

      materialRequest.update((val) {
        val?.items.assignAll(currentItems);
      });

      _markDirty();
    } finally {
      isAddingItem.value = false;
    }
  }

  void deleteItem(MaterialRequestItem item) {
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Remove ${item.itemCode}?',
      onConfirm: () {
        final currentItems = materialRequest.value?.items.toList() ?? [];
        currentItems.remove(item);
        materialRequest.update((val) => val?.items.assignAll(currentItems));
        _markDirty();
      },
    );
  }

  // ── Barcode scan ─────────────────────────────────────────────────────────────────

  Future<void> scanBarcode(String code) async {
    if (code.isEmpty) return;
    if (checkStaleAndBlock()) return;
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted.');
      return;
    }
    if (isItemSheetOpen.value) return;
    if (isScanning.value) return;

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(code);
      if (result.isSuccess && result.itemData != null) {
        openItemSheet(
          newCode: result.itemData!.itemCode,
          newName: result.itemData!.itemName,
          variantOf: result.itemData!.variantOf,
        );
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan Error: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  // ── Save document ───────────────────────────────────────────────────────────────

  Future<void> saveMaterialRequest() async {
    if (isSaving.value) return;
    if (checkStaleAndBlock()) return;

    // isSaving drives the spinner in SaveIconButton; saveResult is set to
    // success or error only after the API call completes.
    isSaving.value = true;

    final data = {
      'material_request_type': selectedType.value,
      'transaction_date': transactionDateController.text,
      'schedule_date': scheduleDateController.text,
      'set_warehouse': setWarehouseController.text,
      'modified': materialRequest.value?.modified,
      'items': materialRequest.value?.items.map((i) {
        final Map<String, dynamic> map = {
          'item_code': i.itemCode,
          'qty': i.qty,
          'schedule_date': scheduleDateController.text,
          'warehouse': i.warehouse,
        };
        final itemName = i.name;
        if (itemName != null && !itemName.startsWith('local_')) {
          map['name'] = itemName;
        }
        return map;
      }).toList(),
    };

    try {
      if (mode == 'new') {
        final response = await _provider.createMaterialRequest(data);
        if (response.statusCode == 200) {
          final created = response.data['data'];
          name = created['name'];
          mode = 'edit';
          await fetchMaterialRequest();
          saveResult.value = SaveResult.success;
          GlobalSnackbar.success(message: 'Material Request Created');
        } else {
          saveResult.value = SaveResult.error;
          GlobalSnackbar.error(message: 'Failed to create request');
        }
      } else {
        final response = await _provider.updateMaterialRequest(name, data);
        if (response.statusCode == 200) {
          await fetchMaterialRequest();
          saveResult.value = SaveResult.success;
          GlobalSnackbar.success(message: 'Material Request Updated');
        } else {
          saveResult.value = SaveResult.error;
          GlobalSnackbar.error(message: 'Failed to update request');
        }
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;

      saveResult.value = SaveResult.error;
      String errorMessage = 'Save failed';
      if (e.response?.data is Map) {
        if (e.response!.data['exception'] != null) {
          errorMessage = e.response!.data['exception']
              .toString()
              .split(':')
              .last
              .trim();
        } else if (e.response!.data['_server_messages'] != null) {
          errorMessage = 'Validation Error: Check form details';
        }
      }
      GlobalSnackbar.error(message: errorMessage);
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }
}
