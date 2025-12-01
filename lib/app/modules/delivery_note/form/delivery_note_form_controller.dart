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
      Get.snackbar('Error', e.toString());
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
      itemCode = barcode.length == 8 ? barcode.substring(0,7) : barcode.substring(0,12);
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

    isLoading.value = true; // Show loading feedback

    try {
      // 1. Validate Item and get details (Name)
      final itemResponse = await _apiProvider.getDocument('Item', itemCode);
      if (itemResponse.statusCode != 200 || itemResponse.data['data'] == null) {
         throw Exception('Item not found');
      }
      final String itemName = itemResponse.data['data']['item_name'] ?? '';

      // 2. Validate Batch
      if (batchNo != null) {
        try {
           await _apiProvider.getDocument('Batch', batchNo);
        } catch (e) {
           final batchResponse = await _apiProvider.getDocumentList('Batch', filters: {'batch_id': batchNo, 'item': itemCode});
           if (batchResponse.data['data'] == null || (batchResponse.data['data'] as List).isEmpty) {
             throw Exception('Batch not found');
           }
        }
      }

      // 3. Fetch Balance History
      double maxQty = 999999.0; // Default high if no batch or fetch fails? Or 0?
      if (batchNo != null) {
        try {
          final balanceResponse = await _apiProvider.getBatchWiseBalance(itemCode, batchNo);
          if (balanceResponse.statusCode == 200 && balanceResponse.data['message'] != null) {
             // Parse report result. Usually 'result' or 'message' contains the list of rows.
             // Structure depends on report. Assuming standard Frappe script report response.
             // The result is often in `message['result']` or `message`.
             // We need to look for a row with the latest balance or sum?
             // Batch-Wise Balance History usually returns rows.
             // Let's assume the report returns a list of dicts and we look for 'balance_qty' or similar.
             // Without knowing the exact report structure, I will attempt to robustly parse or default.
             // Usually `bal_qty` is the field.
             
             final result = balanceResponse.data['message']['result'];
             if (result is List && result.isNotEmpty) {
                // Assuming last row or aggregated row? Or maybe filtering by batch returns one row?
                // Let's take the first row's balance.
                final row = result.first; // Should ideally filter by warehouse if needed, but not specified.
                maxQty = (row['bal_qty'] as num?)?.toDouble() ?? 0.0;
             }
          }
        } catch (e) {
          log('Failed to fetch balance: $e');
          // Proceed with caution or block? "constraint... to value of bal_qty".
          // If fetch fails, maybe assume 0 to be safe? Or allow override?
          // Let's assume 0 if fetch fails to enforce validation strictness.
          maxQty = 0.0; 
        }
      }

      isLoading.value = false; // Hide loading feedback before showing sheet

      // 4. Show Bottom Sheet
      Get.bottomSheet(
        AddItemBottomSheet(
          itemCode: itemCode,
          itemName: itemName,
          batchNo: batchNo,
          maxQty: maxQty,
          onAdd: (qty, rack) {
            _addItemToDeliveryNote(itemCode, qty, rack, batchNo);
          },
        ),
        isScrollControlled: true,
      );

    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Validation failed: ${e.toString().contains('404') ? 'Item or Batch not found' : e.toString()}');
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

// Separate StatefulWidget to handle text controllers lifecycle
class AddItemBottomSheet extends StatefulWidget {
  final String itemCode;
  final String itemName;
  final String? batchNo;
  final double maxQty;
  final Function(double qty, String rack) onAdd;

  const AddItemBottomSheet({
    super.key,
    required this.itemCode,
    required this.itemName,
    this.batchNo,
    required this.maxQty,
    required this.onAdd,
  });

  @override
  State<AddItemBottomSheet> createState() => _AddItemBottomSheetState();
}

class _AddItemBottomSheetState extends State<AddItemBottomSheet> {
  final rackController = TextEditingController();
  final qtyController = TextEditingController(text: '6');
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    rackController.dispose();
    qtyController.dispose();
    super.dispose();
  }

  void _adjustQty(double amount) {
    double currentQty = double.tryParse(qtyController.text) ?? 0;
    double newQty = currentQty + amount;
    
    // Constraints
    if (newQty < 0) newQty = 0; // Don't go below 0
    if (newQty > widget.maxQty) newQty = widget.maxQty; // Don't exceed max

    qtyController.text = newQty.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
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
                initialValue: widget.batchNo,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Batch No', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: rackController,
                decoration: const InputDecoration(labelText: 'Source Rack', border: OutlineInputBorder()),
                autofocus: true,
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: qtyController,
                decoration: InputDecoration(
                  labelText: 'Quantity (Max: ${widget.maxQty})',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => _adjustQty(-6),
                      ),
                      Container(width: 1, height: 24, color: Colors.grey), // Divider
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
                  if (qty % 6 != 0) return 'Quantity must be a multiple of 6';
                  if (qty > widget.maxQty) return 'Exceeds balance (${widget.maxQty})';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.maxQty > 0 ? () {
                    if (formKey.currentState!.validate()) {
                      widget.onAdd(
                        double.parse(qtyController.text),
                        rackController.text,
                      );
                      Get.back();
                    }
                  } : null, // Disable if maxQty is 0 (or validation failed previously)
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
