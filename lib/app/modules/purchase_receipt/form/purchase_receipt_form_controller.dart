import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/purchase_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_item_form_sheet.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final PurchaseOrderProvider _poProvider = Get.find<PurchaseOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final ScanService _scanService = Get.find<ScanService>();

  var itemFormKey = GlobalKey<FormState>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;

  var isDirty = false.obs;
  var isFormDirty = false.obs;

  var purchaseReceipt = Rx<PurchaseReceipt?>(null);
  var linkedPurchaseOrder = Rx<PurchaseOrder?>(null);

  bool get isEditable => purchaseReceipt.value?.docstatus == 0;

  var poItemQuantities = <String, double>{}.obs;

  final supplierController = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  var setWarehouse = RxnString();

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  final TextEditingController barcodeController = TextEditingController();

  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();

  var isItemSheetOpen = false.obs;
  var bsMaxQty = 0.0.obs;

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var bsIsLoadingBatch = false.obs;
  var isValidatingBatch = false.obs;

  var isTargetRackValid = false.obs;
  var isValidatingTargetRack = false.obs;
  var isValidatingSourceRack = false.obs;

  var isSheetValid = false.obs;

  var currentOwner = '';
  var currentCreation = '';
  var currentModifiedBy = '';
  var currentModified = '';
  var currentItemCode = '';
  var currentVariantOf = '';
  var currentItemName = '';
  var currentUom = '';
  var currentItemIdx = 0.obs;
  var currentPurchaseOrderQty = 0.0.obs;
  var currentPoItem = '';
  var currentPoName = '';

  var currentItemNameKey = RxnString();
  var warehouse = RxnString();

  final targetRackFocusNode = FocusNode();
  final batchFocusNode = FocusNode();

  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';

  String currentScannedEan = '';
  var recentlyAddedItemName = ''.obs;

  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> itemKeys = {};

  // Add Metadata Observables
  var bsItemOwner = RxnString();
  var bsItemCreation = RxnString();
  var bsItemModified = RxnString();
  var bsItemModifiedBy = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();

    supplierController.addListener(_markDirty);
    postingDateController.addListener(_markDirty);
    postingTimeController.addListener(_markDirty);
    ever(setWarehouse, (_) => _markDirty());

    bsQtyController.addListener(validateSheet);
    bsBatchController.addListener(validateSheet);
    bsRackController.addListener(validateSheet);

    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchPurchaseReceipt();
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value && isEditable) {
      isDirty.value = true;
    }
  }

  @override
  void onClose() {
    supplierController.dispose();
    postingDateController.dispose();
    postingTimeController.dispose();
    bsQtyController.dispose();
    bsBatchController.dispose();
    bsRackController.dispose();
    barcodeController.dispose();
    targetRackFocusNode.dispose();
    batchFocusNode.dispose();
    super.onClose();
  }

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Warehouse', filters: {'is_group': 0}, limit: 100);
      if (response.statusCode == 200 && response.data['data'] != null) {
        warehouses.value = (response.data['data'] as List).map((e) => e['name'] as String).toList();
      }
    } catch (e) {
      print('Error fetching warehouses: $e');
    } finally {
      isFetchingWarehouses.value = false;
    }
  }

  void _initNewPurchaseReceipt() {
    isLoading.value = true;
    final now = DateTime.now();
    final supplier = Get.arguments['supplier'] ?? '';
    final poName = Get.arguments['purchaseOrder'];

    purchaseReceipt.value = PurchaseReceipt(
      name: 'New Purchase Receipt',
      owner: '',
      creation: now.toString(),
      modified: '',
      docstatus: 0,
      status: 'Draft',
      supplier: supplier,
      postingDate: DateFormat('yyyy-MM-dd').format(now),
      postingTime: DateFormat('HH:mm:ss').format(now),
      setWarehouse: '',
      currency: 'AED',
      totalQty: 0,
      grandTotal: 0.0,
      items: [],
    );

    supplierController.text = supplier;
    postingDateController.text = DateFormat('yyyy-MM-dd').format(now);
    postingTimeController.text = DateFormat('HH:mm:ss').format(now);

    if (poName != null && poName.isNotEmpty) {
      _fetchLinkedPurchaseOrders([poName]);
    }

    isLoading.value = false;
    isDirty.value = false;
  }

  Future<void> fetchPurchaseReceipt() async {
    isLoading.value = true;
    try {
      final response = await _provider.getPurchaseReceipt(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final receipt = PurchaseReceipt.fromJson(response.data['data']);
        purchaseReceipt.value = receipt;

        supplierController.text = receipt.supplier;
        postingDateController.text = receipt.postingDate;
        postingTimeController.text = receipt.postingTime;
        setWarehouse.value = receipt.setWarehouse;

        final poNames = receipt.items
            .map((i) => i.purchaseOrder)
            .where((name) => name != null && name.isNotEmpty)
            .whereType<String>()
            .toSet()
            .toList();

        if (poNames.isNotEmpty) {
          await _fetchLinkedPurchaseOrders(poNames);
        }
      } else {
        GlobalSnackbar.error(message: 'Failed to fetch purchase receipt');
      }
    } catch (e) {
      GlobalSnackbar.error(message: e.toString());
    } finally {
      isLoading.value = false;
      isDirty.value = false;
    }
  }

  Future<void> _fetchLinkedPurchaseOrders(List<String> poNames) async {
    for (var poName in poNames) {
      try {
        final response = await _poProvider.getPurchaseOrder(poName);
        if (response.statusCode == 200 && response.data['data'] != null) {
          final po = PurchaseOrder.fromJson(response.data['data']);
          for (var item in po.items) {
            if (item.name != null) {
              poItemQuantities[item.name!] = item.qty;
            }
          }
        }
      } catch (e) {
        print('Failed to fetch linked PO $poName: $e');
      }
    }
  }

  double getOrderedQty(String? poItemName) {
    if (poItemName == null) return 0.0;
    return poItemQuantities[poItemName] ?? 0.0;
  }

  Future<void> savePurchaseReceipt() async {
    if (!isEditable) return;
    if (isSaving.value) return;
    isSaving.value = true;

    final Map<String, dynamic> data = {
      'supplier': supplierController.text,
      'posting_date': purchaseReceipt.value?.postingDate,
      'posting_time': purchaseReceipt.value?.postingTime,
      'set_warehouse': setWarehouse.value,
    };

    final itemsJson = purchaseReceipt.value?.items.map((i) {
      final json = i.toJson();
      if (json['name'] != null && json['name'].toString().startsWith('local_')) {
        json.remove('name');
      }
      return json;
    }).toList() ?? [];

    data['items'] = itemsJson;

    try {
      if (mode == 'new') {
        final response = await _provider.createPurchaseReceipt(data);
        if (response.statusCode == 200) {
          final createdDoc = response.data['data'];
          name = createdDoc['name'];
          mode = 'edit';

          await fetchPurchaseReceipt();
          GlobalSnackbar.success(message: 'Purchase Receipt created: $name');
        } else {
          GlobalSnackbar.error(message: 'Failed to create: ${response.data['exception'] ?? 'Unknown error'}');
        }
      } else {
        final response = await _provider.updatePurchaseReceipt(name, data);
        if (response.statusCode == 200) {
          GlobalSnackbar.success(message: 'Purchase Receipt updated');
          await fetchPurchaseReceipt();
        } else {
          GlobalSnackbar.error(message: 'Failed to update: ${response.data['exception'] ?? 'Unknown error'}');
        }
      }
    } on DioException catch (e) {
      String errorMessage = 'Save failed';
      if (e.response != null && e.response!.data != null) {
        if (e.response!.data is Map && e.response!.data['exception'] != null) {
          errorMessage = e.response!.data['exception'].toString().split(':').last.trim();
        } else if (e.response!.data is Map && e.response!.data['_server_messages'] != null) {
          errorMessage = 'Validation Error: Check form details';
        }
      }
      GlobalSnackbar.error(message: errorMessage);
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (!isEditable) {
      GlobalSnackbar.warning(message: 'Document is submitted.');
      return;
    }
    if (barcode.isEmpty) return;

    String? contextItem;
    if (isItemSheetOpen.value) {
      contextItem = currentScannedEan.isNotEmpty ? currentScannedEan : currentItemCode;
    }

    if (isItemSheetOpen.value) {
      barcodeController.clear();

      final result = await _scanService.processScan(barcode, contextItemCode: contextItem);

      if (result.type == ScanType.rack && result.rackId != null) {
        bsRackController.text = result.rackId!;
        validateRack(result.rackId!);
      } else if (result.batchNo != null) {
        bsBatchController.text = result.batchNo!;
        validateBatch(result.batchNo!);
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Invalid input for this field');
      }
      return;
    }

    isScanning.value = true;
    try {
      final result = await _scanService.processScan(barcode);

      if (result.isSuccess && result.itemData != null) {
        if (result.rawCode.contains('-') && !result.rawCode.startsWith('SHIPMENT')) {
          currentScannedEan = result.rawCode.split('-')[0];
        } else {
          currentScannedEan = result.rawCode;
        }

        final itemData = result.itemData!;
        currentItemCode = itemData.itemCode;
        currentVariantOf = itemData.variantOf ?? '';
        currentItemName = itemData.itemName;
        currentUom = itemData.stockUom ?? 'Nos';

        currentOwner = '';
        currentCreation = '';
        currentModified = '';
        currentModifiedBy = '';
        currentItemIdx.value = 0;
        currentPurchaseOrderQty.value = 0.0;
        currentPoItem = '';
        currentPoName = '';

        _openQtySheet(scannedBatch: result.batchNo);
      } else {
        GlobalSnackbar.error(message: result.message ?? 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openQtySheet({String? scannedBatch}) {
    itemFormKey = GlobalKey<FormState>();
    bsQtyController.clear();
    bsBatchController.clear();
    bsRackController.clear();

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    bsIsLoadingBatch.value = false;

    isTargetRackValid.value = false;
    isSheetValid.value = false;

    bsItemOwner.value = null;
    bsItemCreation.value = null;
    bsItemModified.value = null;
    bsItemModifiedBy.value = null;

    currentItemNameKey.value = null;
    warehouse.value = null;

    _initialBatch = '';
    _initialRack = '';
    _initialQty = '';
    isFormDirty.value = false;

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
    }

    if (currentItemNameKey.value == null) {
      _initialBatch = '';
      _initialRack = '';
      _initialQty = '';
    }

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return PurchaseReceiptItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
    });
  }

  void validateSheet() {
    if (!isEditable) {
      isSheetValid.value = true;
      return;
    }

    final qty = double.tryParse(bsQtyController.text) ?? 0;
    bool valid = true;
    if (qty <= 0) valid = false;

    if (bsBatchController.text.isNotEmpty && !bsIsBatchValid.value) valid = false;
    if (bsRackController.text.isEmpty || !isTargetRackValid.value) valid = false;

    if (currentItemNameKey.value != null) {
      bool changed = false;
      if (bsBatchController.text != _initialBatch) changed = true;
      if (bsRackController.text != _initialRack) changed = true;
      if (bsQtyController.text != _initialQty) changed = true;
      isFormDirty.value = changed;
      if (!changed) valid = false;
    } else {
      isFormDirty.value = true;
    }

    isSheetValid.value = valid;
  }

  void onRackChanged(String val) {
    if (isTargetRackValid.value) {
      isTargetRackValid.value = false;
    }
    validateSheet();
  }

  void adjustSheetQty(double delta) {
    if (!isEditable) return;
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta).clamp(0.0, 999999.0);
    bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
  }

  Future<void> validateBatch(String batch) async {
    if (!isEditable) return;
    if (batch.isEmpty) return;

    bsIsLoadingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch
      }, fields: ['name', 'custom_packaging_qty']);

      bsIsBatchValid.value = true;
      bsIsBatchReadOnly.value = true;

      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        final batchData = response.data['data'][0];
        GlobalSnackbar.success(message: 'Existing Batch found');

        final double pkgQty = (batchData['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0;
        if (pkgQty > 0) {
          bsQtyController.text = pkgQty % 1 == 0 ? pkgQty.toInt().toString() : pkgQty.toString();
        }
      } else {
        GlobalSnackbar.info(message: 'New Batch will be created');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error validating batch');
      bsIsBatchValid.value = false;
    } finally {
      bsIsLoadingBatch.value = false;
      validateSheet();
    }
  }

  void resetBatchValidation() {
    if (!isEditable) return;
    bsIsBatchValid.value = false;
    bsIsBatchReadOnly.value = false;
    validateSheet();
  }

  Future<void> validateRack(String rack) async {
    if (!isEditable) return;
    if (rack.isEmpty) {
      isTargetRackValid.value = false;
      validateSheet();
      return;
    }

    isValidatingTargetRack.value = true;

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        warehouse.value = wh;
      }
    }

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        isTargetRackValid.value = true;
        GlobalSnackbar.success(message: 'Rack Validated');
      } else {
        isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isTargetRackValid.value = false;
      GlobalSnackbar.error(message: 'Validation failed');
    } finally {
      isValidatingTargetRack.value = false;
      validateSheet();
    }
  }

  void resetRackValidation() {
    if (!isEditable) return;
    isTargetRackValid.value = false;
    validateSheet();
  }

  void editItem(PurchaseReceiptItem item) {
    currentItemNameKey.value = item.name;

    bsItemOwner.value = item.owner;
    bsItemCreation.value = item.creation;
    bsItemModified.value = item.modified;
    bsItemModifiedBy.value = item.modifiedBy;

    currentOwner = item.owner;
    currentCreation = item.creation;
    currentModified = item.modified ?? '';
    currentModifiedBy = item.modifiedBy ?? '';
    currentItemCode = item.itemCode;
    currentItemName = item.itemName ?? '';
    currentVariantOf = item.customVariantOf ?? '';
    currentItemIdx.value = item.idx;
    currentUom = item.uom ?? '';

    currentPoItem = item.purchaseOrderItem ?? '';
    currentPoName = item.purchaseOrder ?? '';
    currentPurchaseOrderQty.value = getOrderedQty(currentPoItem);

    _initialQty = item.qty.toString();
    _initialBatch = item.batchNo ?? '';
    _initialRack = item.rack ?? '';

    bsQtyController.text = _initialQty;
    bsBatchController.text = _initialBatch;
    bsRackController.text = _initialRack;

    warehouse.value = item.warehouse;

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    isTargetRackValid.value = item.rack != null && item.rack!.isNotEmpty;

    validateSheet();

    isItemSheetOpen.value = true;

    Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return PurchaseReceiptItemFormSheet(scrollController: scrollController);
        },
      ),
      isScrollControlled: true,
    ).whenComplete(() {
      isItemSheetOpen.value = false;
      currentItemNameKey.value = null;
    });
  }

  void deleteItem(String uniqueName) {
    if (!isEditable) return;

    final item = purchaseReceipt.value?.items.firstWhereOrNull((i) => i.name == uniqueName);
    if (item == null) return;

    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Remove ${item.itemCode} from the receipt?',
      onConfirm: () {
        final currentItems = purchaseReceipt.value?.items.toList() ?? [];
        currentItems.removeWhere((i) => i.name == uniqueName);

        purchaseReceipt.update((val) {
          val?.items.assignAll(currentItems);
        });

        isDirty.value = true;
        GlobalSnackbar.success(message: 'Item removed');
      },
    );
  }

  void triggerHighlight(String uniqueId) {
    recentlyAddedItemName.value = uniqueId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final key = itemKeys[uniqueId];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
        }
      });
    });

    Future.delayed(const Duration(seconds: 2), () {
      recentlyAddedItemName.value = '';
    });
  }

  void addItem() async {
    if (!isEditable) return;

    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    final rack = bsRackController.text;

    // Determine Warehouse
    String finalWarehouse = warehouse.value ?? '';
    if (finalWarehouse.isEmpty) finalWarehouse = setWarehouse.value ?? '';

    final String uniqueId = currentItemNameKey.value ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    final currentItems = purchaseReceipt.value?.items.toList() ?? [];

    // 1. Check if explicitly editing
    final editIndex = currentItems.indexWhere((i) => i.name == uniqueId);

    if (editIndex != -1) {
      final existing = currentItems[editIndex];
      currentItems[editIndex] = existing.copyWith(
        qty: qty,
        batchNo: batch,
        rack: rack,
        warehouse: finalWarehouse.isNotEmpty ? finalWarehouse : existing.warehouse,
      );
    } else {
      // 2. Check for DUPLICATE (Item + Batch + Rack + Warehouse)
      final duplicateIndex = currentItems.indexWhere((i) {
        return i.itemCode == currentItemCode &&
            (i.batchNo ?? '') == batch &&
            (i.rack ?? '') == rack &&
            (i.warehouse) == finalWarehouse;
      });

      if (duplicateIndex != -1) {
        // MERGE
        final existing = currentItems[duplicateIndex];
        currentItems[duplicateIndex] = existing.copyWith(
            qty: existing.qty + qty
        );
        // Use existing item's ID for highlighting
        currentItemNameKey.value = existing.name;
      } else {
        // ADD NEW
        currentItems.add(PurchaseReceiptItem(
          name: uniqueId,
          owner: currentOwner,
          creation: DateTime.now().toString(),
          itemCode: currentItemCode,
          qty: qty,
          itemName: currentItemName,
          batchNo: batch,
          rack: rack,
          warehouse: finalWarehouse,
          uom: currentUom,
          stockUom: currentUom,
          customVariantOf: currentVariantOf,
          purchaseOrderItem: currentPoItem.isNotEmpty ? currentPoItem : null,
          purchaseOrder: currentPoName.isNotEmpty ? currentPoName : null,
          purchaseOrderQty: currentPurchaseOrderQty.value > 0 ? currentPurchaseOrderQty.value : null,
          idx: currentItems.length + 1,
        ));
      }
    }

    final old = purchaseReceipt.value!;
    purchaseReceipt.value = PurchaseReceipt(
      name: old.name,
      postingDate: old.postingDate,
      modified: old.modified,
      creation: old.creation,
      status: old.status,
      docstatus: old.docstatus,
      owner: old.owner,
      postingTime: old.postingTime,
      setWarehouse: old.setWarehouse,
      supplier: old.supplier,
      currency: old.currency,
      totalQty: old.totalQty,
      grandTotal: old.grandTotal,
      items: currentItems,
    );

    Get.back();
    barcodeController.clear();

    // Trigger Highlight with the correct ID (either new or existing)
    triggerHighlight(currentItemNameKey.value ?? uniqueId);

    if (mode == 'new') {
      savePurchaseReceipt();
    } else {
      isDirty.value = true;
      await savePurchaseReceipt();
      GlobalSnackbar.success(message: 'Item updated');
    }
  }
}