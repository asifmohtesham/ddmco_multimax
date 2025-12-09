import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/providers/purchase_receipt_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_item_form_sheet.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class PurchaseReceiptFormController extends GetxController {
  final PurchaseReceiptProvider _provider = Get.find<PurchaseReceiptProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  String name = Get.arguments['name'];
  String mode = Get.arguments['mode'];

  var isLoading = true.obs;
  var isScanning = false.obs;
  var isSaving = false.obs;

  // Dirty Check State
  var isDirty = false.obs; // For the main document form
  var isFormDirty = false.obs; // For the bottom sheet item form

  var purchaseReceipt = Rx<PurchaseReceipt?>(null);

  // Form Fields
  final supplierController = TextEditingController();
  final postingDateController = TextEditingController();
  final postingTimeController = TextEditingController();
  var setWarehouse = RxnString();

  var warehouses = <String>[].obs;
  var isFetchingWarehouses = false.obs;

  final TextEditingController barcodeController = TextEditingController();

  // Bottom Sheet State
  final bsQtyController = TextEditingController();
  final bsBatchController = TextEditingController();
  final bsRackController = TextEditingController();

  // Context State
  var isItemSheetOpen = false.obs;

  var bsIsBatchReadOnly = false.obs;
  var bsIsBatchValid = false.obs;
  var isValidatingBatch = false.obs;

  // Validation States
  var isSourceRackValid = false.obs;
  var isTargetRackValid = false.obs;
  var isValidatingSourceRack = false.obs;
  var isValidatingTargetRack = false.obs;

  // Item Editing State
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

  // Unique ID for the item being edited (Real Name or local_ ID)
  var currentItemNameKey = RxnString();
  var warehouse = RxnString();

  final targetRackFocusNode = FocusNode();

  // Track initial values for dirty check in bottom sheet
  String _initialBatch = '';
  String _initialRack = '';
  String _initialQty = '';

  @override
  void onInit() {
    super.onInit();
    fetchWarehouses();

    // Dirty Check Listeners for Main Form
    supplierController.addListener(_markDirty);
    postingDateController.addListener(_markDirty);
    postingTimeController.addListener(_markDirty);
    ever(setWarehouse, (_) => _markDirty());

    if (mode == 'new') {
      _initNewPurchaseReceipt();
    } else {
      fetchPurchaseReceipt();
    }
  }

  void _markDirty() {
    if (!isLoading.value && !isDirty.value) {
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

  Future<void> savePurchaseReceipt() async {
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
    } catch (e) {
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> scanBarcode(String barcode) async {
    if (barcode.isEmpty) return;

    if (isItemSheetOpen.value) {
      bsBatchController.text = barcode;
      validateBatch(barcode);
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

    try {
      final response = await _apiProvider.getDocument('Item', itemCode);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final itemData = response.data['data'];
        currentItemCode = itemData['item_code'];
        currentVariantOf = itemData['variant_of'] ?? '';
        currentItemName = itemData['item_name'];
        currentUom = itemData['stock_uom'] ?? 'Nos';
        currentPurchaseOrderQty.value = 0.0;

        currentOwner = '';
        currentCreation = '';
        currentModified = '';
        currentModifiedBy = '';
        currentItemIdx.value = 0;

        _openBottomSheet(scannedBatch: batchNo);
      } else {
        GlobalSnackbar.error(message: 'Item not found');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Scan failed: $e');
    } finally {
      isScanning.value = false;
      barcodeController.clear();
    }
  }

  void _openBottomSheet({String? scannedBatch}) {
    bsQtyController.clear();
    bsBatchController.clear();
    bsRackController.clear();

    bsIsBatchReadOnly.value = false;
    bsIsBatchValid.value = false;
    isValidatingBatch.value = false;
    isTargetRackValid.value = false;

    currentItemNameKey.value = null; // New Item Mode
    warehouse.value = null;

    _initialBatch = '';
    _initialRack = '';
    _initialQty = '';
    isFormDirty.value = false;

    if (scannedBatch != null) {
      bsBatchController.text = scannedBatch;
      validateBatch(scannedBatch);
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

  void checkForChanges() {
    bool dirty = false;
    if (bsBatchController.text != _initialBatch) dirty = true;
    if (bsRackController.text != _initialRack) dirty = true;
    if (bsQtyController.text != _initialQty) dirty = true;

    if (currentItemNameKey.value == null && bsQtyController.text.isNotEmpty) dirty = true;

    isFormDirty.value = dirty;
  }

  void adjustSheetQty(double delta) {
    final current = double.tryParse(bsQtyController.text) ?? 0;
    final newVal = (current + delta).clamp(0.0, 999999.0);
    bsQtyController.text = newVal == 0 ? '' : newVal.toStringAsFixed(0);
    checkForChanges();
  }

  Future<void> validateBatch(String batch) async {
    if (batch.isEmpty) return;

    isValidatingBatch.value = true;
    try {
      final response = await _apiProvider.getDocumentList('Batch', filters: {
        'item': currentItemCode,
        'name': batch
      });

      bsIsBatchValid.value = true;
      bsIsBatchReadOnly.value = true;

      if (response.statusCode == 200 && response.data['data'] != null && (response.data['data'] as List).isNotEmpty) {
        GlobalSnackbar.success(message: 'Existing Batch found');
      } else {
        GlobalSnackbar.info(message: 'New Batch will be created');
      }

      checkForChanges();
      _focusNextField();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to check batch: $e');
      bsIsBatchValid.value = false;
    } finally {
      isValidatingBatch.value = false;
    }
  }

  Future<void> validateRack(String rack, bool isSource) async {
    if (rack.isEmpty) return;

    if (rack.contains('-')) {
      final parts = rack.split('-');
      if (parts.length >= 3) {
        final wh = '${parts[1]}-${parts[2]} - ${parts[0]}';
        warehouse.value = wh;
      }
    }

    // Since this is receipt, we are targeting a rack
    isValidatingTargetRack.value = true;

    try {
      final response = await _apiProvider.getDocument('Rack', rack);
      if (response.statusCode == 200 && response.data['data'] != null) {
        isTargetRackValid.value = true;
      } else {
        isTargetRackValid.value = false;
        GlobalSnackbar.error(message: 'Rack not found');
      }
    } catch (e) {
      isTargetRackValid.value = false;
    } finally {
      isValidatingTargetRack.value = false;
      checkForChanges();
    }
  }

  void _focusNextField() {
    targetRackFocusNode.requestFocus();
  }

  void editItem(PurchaseReceiptItem item) {
    currentItemNameKey.value = item.name;
    currentOwner = item.owner;
    currentCreation = item.creation;
    currentModified = item.modified ?? '';
    currentModifiedBy = item.modifiedBy ?? '';
    currentItemCode = item.itemCode;
    currentItemName = item.itemName ?? '';
    currentVariantOf = item.customVariantOf ?? '';
    currentItemIdx.value = item.idx;
    currentPurchaseOrderQty.value = item.purchaseOrderQty ?? 0.0;

    _initialQty = item.qty.toString();
    _initialBatch = item.batchNo ?? '';
    _initialRack = item.rack ?? '';

    bsQtyController.text = _initialQty;
    bsBatchController.text = _initialBatch;
    bsRackController.text = _initialRack;

    warehouse.value = item.warehouse;

    bsIsBatchValid.value = true;
    bsIsBatchReadOnly.value = true;
    isFormDirty.value = false;

    isTargetRackValid.value = item.rack != null && item.rack!.isNotEmpty;

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
    final currentItems = purchaseReceipt.value?.items.toList() ?? [];
    currentItems.removeWhere((i) => i.name == uniqueName);

    purchaseReceipt.update((val) {
      val?.items.assignAll(currentItems);
    });

    isDirty.value = true;
    GlobalSnackbar.success(message: 'Item removed');
  }

  void addItem() {
    final double qty = double.tryParse(bsQtyController.text) ?? 0;
    if (qty <= 0) return;

    final batch = bsBatchController.text;
    if (!bsIsBatchValid.value && batch.isNotEmpty) return;

    final String uniqueId = currentItemNameKey.value ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

    final currentItems = purchaseReceipt.value?.items.toList() ?? [];

    final index = currentItems.indexWhere((i) => i.name == uniqueId);

    if (index != -1) {
      final existing = currentItems[index];
      currentItems[index] = existing.copyWith(
        qty: qty,
        batchNo: batch,
        rack: bsRackController.text,
        warehouse: warehouse.value!.isNotEmpty ? warehouse.value! : existing.warehouse,
      );
    } else {
      currentItems.add(PurchaseReceiptItem(
        name: uniqueId,
        owner: currentOwner,
        creation: DateTime.now().toString(),
        itemCode: currentItemCode,
        qty: qty,
        itemName: currentItemName,
        batchNo: batch,
        rack: bsRackController.text,
        warehouse: warehouse.value ?? '',
        customVariantOf: currentVariantOf,
        purchaseOrderQty: currentPurchaseOrderQty.value,
        idx: currentItems.length + 1,
      ));
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

    if (mode == 'new') {
      savePurchaseReceipt();
    } else {
      isDirty.value = true;
      GlobalSnackbar.success(message: index != -1 ? 'Item updated' : 'Item added');
    }
  }
}