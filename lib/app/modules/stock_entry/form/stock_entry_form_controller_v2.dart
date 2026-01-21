import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/stock_entry_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class StockEntryFormControllerV2 extends GetxController {
  final StockEntryProvider _provider = Get.find<StockEntryProvider>();

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