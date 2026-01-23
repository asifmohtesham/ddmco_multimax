import 'dart:convert';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class StockEntryFormControllerV2 extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // --- Controllers ---
  // Dedicated controller for the barcode field to manage cursor focus and clearing
  final TextEditingController scanBarcodeController = TextEditingController();

  // --- State for Business Logic ---
  // Stores the last scanned EAN8 to support split scanning (EAN first, then Batch ID)
  var pendingEan8 = RxnString();

  // --- Configuration: Form Visibility (Edit Sheet) ---
  static const Map<String, List<String>> _visibleFields = {
    'Stock Entry': [
      // Data Fields
      'stock_entry_details_tab',
      'stock_entry_type',
      'purpose',
      'from_warehouse',
      'to_warehouse',
      'scan_barcode',
      'items_section',
      'items',
      'other_info_tab',
      'more_info',
      'custom_reference_no'
      // Note: 'posting_date' and 'company' removed for simplicity (layman view),
      // assuming they are auto-set or hidden. Add back if needed.
    ],
    'Stock Entry Detail': [
      'custom_invoice_serial_number',
      'barcode',
      'custom_variant_of',
      'item_code',
      'item_group',
      'item_name',
      'qty',
      'uom',
      's_warehouse',
      't_warehouse',
      'rack',
      'to_rack',
      'use_serial_batch_fields',
      'batch_no',
      'serial_and_batch_bundle'
    ],
  };

  // --- Configuration: List Visibility (Table Row Summary) ---
  // Fields listed here will have 'in_list_view' set to 1.
  static const Map<String, List<String>> _listFields = {
    'Stock Entry Detail': [
      'custom_invoice_serial_number',
      'barcode',
      'custom_variant_of',
      'item_group',
      'item_name',
      'rack',
      'to_rack',
      'batch_no', // Useful to see batch in summary without opening
      'qty',
    ],
  };

  // --- State ---
  var isLoading = true.obs;
  var isSaving = false.obs;

  var doc = <String, dynamic>{}.obs;
  Map<String, dynamic> _serverDoc = {};

  var metaFields = <Map<String, dynamic>>[].obs;
  var itemMetaFields = <Map<String, dynamic>>[].obs;

  Map<String, List<Map<String, dynamic>>> get childMetaMap => {
    'Stock Entry Detail': itemMetaFields,
  };

  bool get isDirty => !const DeepCollectionEquality().equals(doc, _serverDoc);

  String name = Get.arguments?['name'] ?? '';

  @override
  void onInit() {
    super.onInit();
    _initForm();
  }

  Future<void> _initForm() async {
    isLoading.value = true;
    try {
      final metaResponse = await _provider.getMeta();
      if (metaResponse.statusCode == 200) {
        List<dynamic> rawFields = metaResponse.data['data']['fields'] ?? [];

        // Filter Parent Fields
        metaFields.assignAll(_filterAndProcessFields(rawFields, 'Stock Entry'));

        // Fetch Child Meta
        await _fetchChildMeta();
      }

      if (name.isNotEmpty && name != 'new') {
        final docResponse = await _provider.getStockEntry(name);
        if (docResponse.statusCode == 200) {
          _setServerDoc(docResponse.data['data']);
        }
      } else {
        _setServerDoc(_getNewDocDefaults());
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Stock Entry V2: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchChildMeta() async {
    try {
      final response = await Get.find<ApiProvider>().getDocTypeMeta(
        'Stock Entry Detail',
      );

      if (response.statusCode == 200) {
        List<dynamic> rawChildFields = response.data['data']['fields'] ?? [];
        itemMetaFields.assignAll(
          _filterAndProcessFields(rawChildFields, 'Stock Entry Detail'),
        );
      }
    } catch (e) {
      print('Warning: Could not fetch child meta: $e');
    }
  }

  /// Filters fields for the Form AND applies 'in_list_view' for the List.
  List<Map<String, dynamic>> _filterAndProcessFields(
      List<dynamic> rawFields,
      String docType,
      ) {
    final formWhitelist = _visibleFields[docType] ?? [];
    final listWhitelist = _listFields[docType] ?? [];

    return rawFields.map((e) => Map<String, dynamic>.from(e)).where((field) {
      final name = field['fieldname'];
      return formWhitelist.contains(name);
    }).map((field) {
      // Overwrite 'in_list_view' based on our mobile-specific configuration
      final name = field['fieldname'];
      field['in_list_view'] = listWhitelist.contains(name) ? 1 : 0;
      return field;
    }).toList();
  }

  // --- Barcode Logic (V1 Replication with Fix) ---
  Future<void> processBarcodeScan(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return;

    isLoading.value = true;
    try {
      String? itemCode;
      String? uom;

      // 1. Search in 'Item Barcode' child table
      // Wrapped in try/catch to gracefully handle 403 Permission Errors
      try {
        final barcodeResponse = await _apiProvider.callMethod(
          'frappe.client.get_value',
          params: {
            'doctype': 'Item Barcode',
            'fieldname': ['parent', 'uom'],
            'filters': jsonEncode({'barcode': cleanBarcode.substring(0,7)}),
          },
        );

        if (barcodeResponse.statusCode == 200 &&
            barcodeResponse.data['message'] != null) {
          itemCode = barcodeResponse.data['message']['parent'];
          uom = barcodeResponse.data['message']['uom'];
        }
      } catch (e) {
        // Fallthrough if permission denied or other error
        print('Barcode lookup skipped: $e');
      }

      // 2. Fallback: Search 'Item' DocType directly (By Name)
      if (itemCode == null) {
        try {
          final itemResponse = await _apiProvider.callMethod(
            'frappe.client.get_value',
            params: {
              'doctype': 'Item',
              'fieldname': '*', // Fetch the name (Primary Key)
              // IMPORTANT: Filter by 'name' (not 'item_code') to ensure valid DocName match
              'filters': jsonEncode({'name': cleanBarcode.substring(0,7)}),
            },
          );

          if (itemResponse.statusCode == 200 &&
              itemResponse.data['message'] != null) {

            final message = itemResponse.data['message'];
            // Handle response format (either map or direct value depending on API version/params)
            if (message is Map) {
              itemCode = message['name'];
            } else {
              itemCode = message.toString();
            }
          }
        } catch (e) {
          print('Item lookup skipped: $e');
        }
      }

      if (itemCode == null) {
        GlobalSnackbar.error(message: 'Item not found for barcode: $cleanBarcode');
        return;
      }

      // 3. Process Found Item
      await _addOrUpdateItemRow(itemCode, scannedUom: uom);

      // 4. Cleanup
      doc['scan_barcode'] = '';
      scanBarcodeController.clear();

    } catch (e) {
      GlobalSnackbar.error(message: 'Error scanning barcode: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _addOrUpdateItemRow(String itemCode, {String? scannedUom}) async {
    // A. Fetch Item Details
    final itemDetailsRes = await _apiProvider.getDocument('Item', itemCode);
    if (itemDetailsRes.statusCode != 200) {
      throw Exception("Could not fetch details for $itemCode");
    }
    final itemData = itemDetailsRes.data['data'];

    // B. Check if item exists in current list
    List<dynamic> items = List.from(doc['items'] ?? []);

    // Simple matching logic from V1
    final existingIndex = items.indexWhere((row) =>
    row['item_code'] == itemCode &&
        (scannedUom == null || row['uom'] == scannedUom)
    );

    if (existingIndex != -1) {
      // INCREMENT Quantity
      var row = Map<String, dynamic>.from(items[existingIndex]);
      double currentQty = double.tryParse(row['qty'].toString()) ?? 0;
      row['qty'] = currentQty + 1;
      items[existingIndex] = row;
      GlobalSnackbar.success(message: 'Updated quantity for $itemCode');
    } else {
      // ADD New Row (Dynamic Mapping)
      Map<String, dynamic> newRow = {};

      // 1. Dynamic Mapping:
      // iterate through child table meta (whitelisted fields) and copy matching fields from Item data
      for (var field in itemMetaFields) {
        final String fieldName = field['fieldname'];
        // If the Item document has this field, copy it
        if (itemData.containsKey(fieldName)) {
          newRow[fieldName] = itemData[fieldName];
        } else if (itemData.containsKey(fieldName.replaceAll('custom_', ''))) {
          newRow[fieldName] = itemData[fieldName.replaceAll('custom_', '')];
        }
      }

      // 2. Set Mandatory Overrides & Defaults
      newRow['barcode'] = itemData['barcodes'].where((barcode) => barcode['barcode'].length == 8).first['barcode'];
      newRow['item_code'] = itemCode;
      newRow['custom_invoice_serial_number'] = 0;
      newRow['qty'] = 1.0;
      newRow['s_warehouse'] = doc['from_warehouse'];
      newRow['t_warehouse'] = doc['to_warehouse'];
      newRow['conversion_factor'] = 1.0;

      // 3. Priority for UOM: Scanned > Item Stock UOM
      newRow['uom'] = scannedUom ?? itemData['stock_uom'];
      newRow['stock_uom'] = itemData['stock_uom'];

      // 4. Ensure flags are present (even if not in whitelisted form fields)
      newRow['has_batch_no'] = itemData['has_batch_no'];
      newRow['has_serial_no'] = itemData['has_serial_no'];

      items.insert(0, newRow);
      GlobalSnackbar.success(message: 'Added $itemCode');
    }

    updateField('items', items);
  }

  Map<String, dynamic> _getNewDocDefaults() {
    return {
      'docstatus': 0,
      'naming_series': 'MAT-STE-.YYYY.-',
      'stock_entry_type': 'Material Transfer',
      'posting_date': DateTime.now().toString().split(' ')[0],
      'items': [],
      'company': 'Multimax',
    };
  }

  void _setServerDoc(Map<String, dynamic> data) {
    _serverDoc = Map<String, dynamic>.from(data);
    doc.assignAll(Map<String, dynamic>.from(data));
  }

  void updateField(String fieldName, dynamic value) {
    doc[fieldName] = value;
    doc.refresh();
  }

  List<Map<String, dynamic>> getItems() {
    if (doc['items'] != null && doc['items'] is List) {
      return List<Map<String, dynamic>>.from(doc['items']);
    }
    return [];
  }

  void updateRow(int index, Map<String, dynamic> rowData) {
    List<dynamic> items = List.from(doc['items'] ?? []);
    if (index >= 0 && index < items.length) {
      items[index] = rowData;
      updateField('items', items);
    }
  }

  // --- Updated: Accepts data from the Form Sheet ---
  void addRow(Map<String, dynamic> rowData) {
    List<dynamic> items = List.from(doc['items'] ?? []);

    // Add default values if missing from the form data
    if (rowData['uom'] == null) rowData['uom'] = 'Nos';
    if (rowData['qty'] == null) rowData['qty'] = 0;

    items.add(rowData);
    updateField('items', items);
  }

  void removeRow(int index) {
    List<dynamic> items = List.from(doc['items'] ?? []);
    items.removeAt(index);
    updateField('items', items);
  }

  Future<void> save() async {
    if (isSaving.value) return;
    isSaving.value = true;
    try {
      Response response;
      if (doc['name'] != null) {
        response = await _provider.updateStockEntry(doc['name'], doc);
      } else {
        response = await _provider.createStockEntry(doc);
      }
      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Saved Successfully');
        _setServerDoc(response.data['data']);
        name = doc['name'];
      } else {
        throw Exception(response.data['exception'] ?? 'Unknown Error');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Save Failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> confirmDiscard() async {
    if (!isDirty) {
      Get.back();
      return;
    }
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        Get.back();
        Get.back();
      },
    );
  }
}