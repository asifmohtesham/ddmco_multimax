import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';
import 'dart:developer';
import 'package:ddmco_multimax/app/data/models/delivery_note_model.dart';
import 'package:ddmco_multimax/app/data/providers/delivery_note_provider.dart';
import 'package:ddmco_multimax/app/data/models/pos_upload_model.dart';
import 'package:ddmco_multimax/app/data/providers/pos_upload_provider.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class DeliveryNoteFormController extends GetxController {
  final DeliveryNoteProvider _provider = Get.find<DeliveryNoteProvider>();
  final PosUploadProvider _posUploadProvider = Get.find<PosUploadProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final String name = Get.arguments['name'];
  final String mode = Get.arguments['mode'];
  final String? posUploadCustomer = Get.arguments['posUploadCustomer'];
  final String? posUploadNameArg = Get.arguments['posUploadName'];

  var isLoading = true.obs;
  var deliveryNote = Rx<DeliveryNote?>(null);
  var posUpload = Rx<PosUpload?>(null);

  final TextEditingController barcodeController = TextEditingController();
  var expandedItemCode = ''.obs;
  var expandedInvoice = ''.obs;

  var itemFilter = 'All'.obs;

  @override
  void onInit() {
    super.onInit();
    if (mode == 'new') {
      _createNewDeliveryNote();
    } else {
      fetchDeliveryNote();
    }
  }

  void _createNewDeliveryNote() async {
    isLoading.value = true;
    deliveryNote.value = DeliveryNote(
      name: 'New Delivery Note',
      customer: posUploadCustomer ?? '',
      grandTotal: 0.0,
      postingDate: DateTime.now().toString().split(' ')[0],
      modified: '',
      status: 'Draft',
      currency: 'USD',
      items: [],
      poNo: posUploadNameArg,
    );
    log('[CONTROLLER] New DN created with poNo: ${deliveryNote.value?.poNo}');

    if (posUploadNameArg != null && posUploadNameArg!.isNotEmpty) {
      await fetchPosUpload(posUploadNameArg!);
    }
    isLoading.value = false;
  }

  Future<void> fetchDeliveryNote() async {
    isLoading.value = true;
    try {
      final response = await _provider.getDeliveryNote(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final note = DeliveryNote.fromJson(response.data['data']);
        deliveryNote.value = note;
        log('[CONTROLLER] Fetched DN. poNo from JSON: ${note.poNo}');
        
        if (note.poNo != null && note.poNo!.isNotEmpty) {
          await fetchPosUpload(note.poNo!);
        }
      } else {
        Get.snackbar('Error', 'Failed to fetch delivery note');
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load initial data: ${e.toString()}');
      log('Error loading initial data: $e');
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
      Get.snackbar('Error', 'Failed to fetch linked POS Upload: $e');
    }
  }

  void toggleExpand(String itemCode) {
    expandedItemCode.value = expandedItemCode.value == itemCode ? '' : itemCode;
  }

  void toggleInvoiceExpand(String key) {
    expandedInvoice.value = expandedInvoice.value == key ? '' : key;
  }

  Future<void> addItemFromBarcode(String barcode) async {
    final RegExp eanRegex = RegExp(r'^\d{8,13}$');
    final RegExp batchRegex = RegExp(r'^(\d{8,13})-([a-zA-Z0-9]{3,6})$');

    String itemCode = '';
    String? batchNo;

    if (eanRegex.hasMatch(barcode)) {
      itemCode = barcode;
      itemCode = itemCode.length == 8 ? itemCode.substring(0,7) : itemCode.substring(0,12);
    } else if (batchRegex.hasMatch(barcode)) {
      final match = batchRegex.firstMatch(barcode);
      itemCode = match!.group(1)!;
      itemCode = itemCode.length == 8 ? itemCode.substring(0,7) : itemCode.substring(0,12);
      batchNo = barcode;
    } else {
      Get.snackbar('Error', 'Invalid barcode format. Expected EAN (7-13 digits) or EAN-BATCH (3-6 chars)');
      barcodeController.clear();
      return;
    }

    // Show loading immediately
    isLoading.value = true; 

    try {
      // 1. Validate Item and get details (Name)
      final itemResponse = await _apiProvider.getDocument('Item', itemCode);
      if (itemResponse.statusCode != 200 || itemResponse.data['data'] == null) {
         throw Exception('Item not found');
      }
      final String itemName = itemResponse.data['data']['item_name'] ?? '';

      double maxQty = 0.0;

      // 2. If Batch is present, Validate and Fetch Balance
      if (batchNo != null) {
        try {
           await _apiProvider.getDocument('Batch', batchNo);
        } catch (e) {
           // If direct fetch fails, try searching
           final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': itemCode});
           if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
             throw Exception('Batch not found');
           }
        }

        // Fetch Balance
        try {
          final balanceResponse = await _apiProvider.getBatchWiseBalance(itemCode, batchNo);
          if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
             final result = balanceResponse.data['message']['result'];
             if (result is List && result.isNotEmpty) {
                final row = result.first; 
                maxQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
             }
          }
        } catch (e, stackTrace) {
          log('Failed to fetch balance', error: e, stackTrace: stackTrace);
          maxQty = 6.0; // Fail safe
        }
      }

      isLoading.value = false; // Hide global loading

      // 3. Show Bottom Sheet
      // If batchNo was null, the BottomSheet will handle entry and validation
      Get.bottomSheet(
        AddItemBottomSheet(
          itemCode: itemCode,
          itemName: itemName,
          initialBatchNo: batchNo,
          initialMaxQty: maxQty,
          onAdd: (qty, rack, finalBatchNo) {
            _addItemToDeliveryNote(itemCode, qty, rack, finalBatchNo);
          },
        ),
        isScrollControlled: true,
      );

    } catch (e, stackTrace) {
      isLoading.value = false;
      final errorMessage = 'Validation failed: ${e.toString().contains('404') ? 'Item or Batch not found' : e.toString()}';
      Get.snackbar('Error', errorMessage);
      log(errorMessage, error: e, stackTrace: stackTrace);
    } finally {
      barcodeController.clear();
    }
  }

  void _addItemToDeliveryNote(String itemCode, double qty, String rack, String? batchNo) {
    final newItem = DeliveryNoteItem(
      itemCode: itemCode,
      qty: qty,
      rate: 0.0,
      rack: rack,
      batchNo: batchNo,
      customInvoiceSerialNumber: '0', 
    );
    
    final currentItems = deliveryNote.value?.items.toList() ?? [];
    currentItems.add(newItem);
    
    deliveryNote.value = deliveryNote.value?.copyWith(items: currentItems);
    Get.snackbar('Success', 'Item added');
  }

  Map<String, List<DeliveryNoteItem>> get groupedItems {
    if (deliveryNote.value == null || deliveryNote.value!.items.isEmpty) {
      return {};
    }
    return groupBy(deliveryNote.value!.items, (DeliveryNoteItem item) {
      return item.customInvoiceSerialNumber ?? '0'; 
    });
  }

  // --- Counts for Filtering ---

  int get allCount => posUpload.value?.items.length ?? 0;

  int get completedCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      final cumulativeQty = dnItems.fold(0.0, (sum, item) => sum + item.qty);
      return cumulativeQty >= posItem.quantity;
    }).length;
  }

  int get pendingCount {
    if (posUpload.value == null) return 0;
    final groups = groupedItems;
    return posUpload.value!.items.where((posItem) {
      final serialNumber = (posUpload.value!.items.indexOf(posItem) + 1).toString();
      final dnItems = groups[serialNumber] ?? [];
      final cumulativeQty = dnItems.fold(0.0, (sum, item) => sum + item.qty);
      return cumulativeQty < posItem.quantity;
    }).length;
  }

  void setFilter(String filter) {
    itemFilter.value = filter;
  }
}

// Stateful Widget for Bottom Sheet Logic
class AddItemBottomSheet extends StatefulWidget {
  final String itemCode;
  final String itemName;
  final String? initialBatchNo;
  final double initialMaxQty;
  final Function(double qty, String rack, String batchNo) onAdd;

  const AddItemBottomSheet({
    super.key,
    required this.itemCode,
    required this.itemName,
    this.initialBatchNo,
    required this.initialMaxQty,
    required this.onAdd,
  });

  @override
  State<AddItemBottomSheet> createState() => _AddItemBottomSheetState();
}

class _AddItemBottomSheetState extends State<AddItemBottomSheet> {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  
  late TextEditingController batchController;
  final rackController = TextEditingController();
  final qtyController = TextEditingController(text: '6');
  final formKey = GlobalKey<FormState>();

  bool isBatchReadOnly = false;
  bool isLoadingBatch = false;
  double maxQty = 0.0;
  String? batchError;

  @override
  void initState() {
    super.initState();
    batchController = TextEditingController(text: widget.initialBatchNo ?? '');
    isBatchReadOnly = widget.initialBatchNo != null;
    maxQty = widget.initialMaxQty;
  }

  @override
  void dispose() {
    batchController.dispose();
    rackController.dispose();
    qtyController.dispose();
    super.dispose();
  }

  Future<void> _validateAndFetchBatch(String batchNo) async {
    if (batchNo.isEmpty) return;

    setState(() {
      isLoadingBatch = true;
      batchError = null;
    });

    try {
      // 1. Check if batch exists
      try {
         await _apiProvider.getDocument('Batch', batchNo);
      } catch (e) {
         // Fallback search
         final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': widget.itemCode});
         if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
           throw Exception('Batch not found');
         }
      }

      // 2. Fetch Balance
      final balanceResponse = await _apiProvider.getBatchWiseBalance(widget.itemCode, batchNo);
      double fetchedQty = 0.0;
      if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
         final result = balanceResponse.data['message']['result'];
         if (result is List && result.isNotEmpty) {
            final row = result.first;
            log(row);
            fetchedQty = (row['balance_qty'] as num?)?.toDouble() ?? 0.0;
         }
      }

      setState(() {
        maxQty = fetchedQty;
        isLoadingBatch = false;
      });

    } catch (e, stackTrace) {
      final errorMessage = 'Failed to validate batch: ${e.toString()}';
      log(errorMessage, error: e, stackTrace: stackTrace);
      setState(() {
        isLoadingBatch = false;
        batchError = 'Invalid Batch';
        maxQty = 0.0;
      });
    }
  }

  void _adjustQty(double amount) {
    double currentQty = double.tryParse(qtyController.text) ?? 0;
    double newQty = currentQty + amount;
    
    // Constraints
    if (newQty < 0) newQty = 0; 
    if (newQty > maxQty) newQty = maxQty; 

    qtyController.text = newQty.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.itemCode} - ${widget.itemName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: batchController,
                readOnly: isBatchReadOnly || isLoadingBatch,
                autofocus: !isBatchReadOnly,
                decoration: InputDecoration(
                  labelText: 'Batch No',
                  border: const OutlineInputBorder(),
                  errorText: batchError,
                  suffixIcon: isLoadingBatch
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : (!isBatchReadOnly
                      ? IconButton(
                          icon: const Icon(Icons.check),
                          onPressed: () => _validateAndFetchBatch(batchController.text),
                        ) 
                      : null),
                ),
                onFieldSubmitted: (val) {
                  if (!isBatchReadOnly && !isLoadingBatch) _validateAndFetchBatch(val);
                },
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: rackController,
                decoration: const InputDecoration(labelText: 'Source Rack', border: OutlineInputBorder()),
                // Only autofocus rack if batch is already known
                autofocus: isBatchReadOnly, 
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: qtyController,
                decoration: InputDecoration(
                  labelText: 'Quantity (Max: $maxQty)',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => _adjustQty(-6),
                      ),
                      Container(width: 1, height: 24, color: Colors.grey.shade400),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _adjustQty(6),
                      ),
                    ],
                  ),
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  final qty = double.tryParse(value);
                  if (qty == null) return 'Invalid number';
                  if (qty <= 0) return 'Must be > 0';
                  if (qty % 6 != 0) return 'Must be a multiple of 6';
                  if (qty > maxQty) return 'Exceeds balance ($maxQty)';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  // Disable if loading, maxQty is 0, or batch is empty
                  onPressed: (!isLoadingBatch && maxQty > 0 && batchController.text.isNotEmpty) ? () {
                    if (formKey.currentState!.validate()) {
                      widget.onAdd(
                        double.parse(qtyController.text),
                        rackController.text,
                        batchController.text,
                      );
                      Get.back();
                    }
                  } : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                  child: const Text('Add Item'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
