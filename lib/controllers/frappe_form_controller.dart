import 'package:flutter/material.dart'; // Changed from foundation to material for FormKey
import 'package:get/get.dart';
import '../services/frappe_api.dart';

class FrappeFormController extends GetxController {
  final FrappeApiService _api = FrappeApiService();
  final RxMap<String, dynamic> data = <String, dynamic>{}.obs;
  final String doctype;

  // New: Metadata handling
  final RxList<Map<String, dynamic>> _metaFields = <Map<String, dynamic>>[].obs;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  FrappeFormController({required this.doctype});

  @override
  void onInit() {
    super.onInit();
    _api.init();
    _fetchMetaData();
  }

  // FIX: Fetch DocType definition to know mandatory fields
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

  void initialize(Map<String, dynamic>? initialData) {
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
      Get.snackbar(
        "Error",
        e.toString().replaceAll('Exception:', ''),
        backgroundColor: Get.theme.colorScheme.error.withOpacity(0.1),
        colorText: Get.theme.colorScheme.error,
        duration: const Duration(seconds: 4),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> save() async {
    // 1. UI Validation (if Form widget is used)
    if (formKey.currentState != null && !formKey.currentState!.validate()) {
      Get.snackbar(
        "Validation Error",
        "Please check the form for errors.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
      return;
    }

    // 2. Metadata Validation (Universal Safety Net)
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
              backgroundColor: Colors.orange.withOpacity(0.1),
              colorText: Colors.deepOrange,
            );
            return;
          }
        }
      }
    }

    try {
      await _api.saveDoc(doctype, data);
      Get.snackbar(
        "Success",
        "Saved successfully",
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint("❌ Save Error: $e");
      Get.snackbar(
        "Error",
        "${e.toString().replaceAll('Exception:', '')}",
        backgroundColor: Get.theme.colorScheme.error.withOpacity(0.1),
        colorText: Get.theme.colorScheme.error,
      );
    }
  }

  Future<List<String>> searchLink(String linkDoctype, String query) {
    return _api.searchLink(linkDoctype, query);
  }
}
