import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/frappe_api.dart';
import '../widgets/frappe_error_dialog.dart';

class FrappeFormController extends GetxController {
  final FrappeApiService _api = FrappeApiService();
  final RxMap<String, dynamic> data = <String, dynamic>{}.obs;
  final String doctype;

  // New: Metadata handling
  final RxList<Map<String, dynamic>> _metaFields = <Map<String, dynamic>>[].obs;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  FrappeFormController({required this.doctype});

  // Expose API to subclasses
  FrappeApiService get api => _api;

  @override
  void onInit() {
    super.onInit();
    _api.init();
    _fetchMetaData();
  }

  // Fetch DocType definition to know mandatory fields
  Future<void> _fetchMetaData() async {
    try {
      final docTypeDef = await _api.getDocType(doctype);
      if (docTypeDef['fields'] != null) {
        _metaFields.assignAll(
          List<Map<String, dynamic>>.from(docTypeDef['fields']),
        );
      }
    } catch (e) {
      debugPrint("Warning: Could not fetch metadata for $doctype validation.");
    }
  }

  void initialise(Map<String, dynamic>? initialData) {
    if (initialData != null) {
      data.assignAll(initialData);
    }
  }

  void setValue(String fieldname, dynamic value) {
    data[fieldname] = value;
  }

  /// Retrieve a value safely with intelligent type casting
  T? getValue<T>(String fieldname) {
    if (data[fieldname] == null) return null;
    final val = data[fieldname];
    if (T == double && val is int) return val.toDouble() as T;
    if (T == int && val is double) return val.toInt() as T;
    if (T == String && (val is int || val is double))
      return val.toString() as T;
    return val as T?;
  }

  Future<void> load(String docName) async {
    try {
      data.clear();
      final docData = await _api.getDoc(doctype, docName);
      data.assignAll(docData);
    } catch (e) {
      debugPrint("❌ Error loading $doctype $docName: $e");
      // Use Dialog for load errors too if they are critical
      FrappeErrorDialog.show(title: "Load Failed", error: e);
    }
  }

  Future<void> save() async {
    // 1. Client-Side Validation
    if (formKey.currentState != null && !formKey.currentState!.validate()) {
      Get.snackbar(
        "Validation Error",
        "Please check the form for errors.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.1),
        colorText: Colors.red,
      );
      return;
    }

    // 2. Metadata Validation
    if (_metaFields.isNotEmpty) {
      for (var field in _metaFields) {
        // Check if required (reqd == 1) and not read_only (read_only != 1)
        if ((field['reqd'] == 1) && (field['read_only'] != 1)) {
          final key = field['fieldname'];
          final label = field['label'] ?? key;
          final val = data[key];

          // Check for empty values
          if (val == null ||
              (val is String && val.trim().isEmpty) ||
              (val is List && val.isEmpty)) {
            Get.snackbar(
              "Missing Field",
              "$label is required.",
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange.withValues(alpha: 0.1),
              colorText: Colors.deepOrange,
            );
            return;
          }
        }
      }
    }

    // 3. API Save
    try {
      // Capture returned document and refresh local state
      final savedDoc = await _api.saveDoc(doctype, data);
      data.assignAll(savedDoc);

      Get.snackbar(
        "Success",
        "Saved successfully",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.withValues(alpha: 0.1),
        colorText: Colors.green,
      );
    } catch (e) {
      debugPrint("❌ Save Error: $e");
      // Use the new Error Dialog for readable HTML errors
      FrappeErrorDialog.show(title: "Save Failed", error: e);
    }
  }

  Future<List<String>> searchLink(String linkDoctype, String query) {
    return _api.searchLink(linkDoctype, query);
  }
}
