import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/frappe_api.dart';
import '../widgets/frappe_error_dialog.dart';
import '../models/frappe_field_config.dart';
import '../models/frappe_form_layout_model.dart';

class FrappeFormController extends GetxController {
  final FrappeApiService _api = FrappeApiService();
  final RxMap<String, dynamic> data = <String, dynamic>{}.obs;
  final String doctype;

  // RAW Metadata
  final RxList<Map<String, dynamic>> _metaFields = <Map<String, dynamic>>[].obs;

  // PARSED Layout
  final RxList<FrappeFormSection> layoutSections = <FrappeFormSection>[].obs;
  final RxBool isMetaLoading = true.obs;

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
    isMetaLoading.value = true;
    try {
      final docTypeDef = await _api.getDocType(doctype);
      if (docTypeDef['fields'] != null) {
        final rawFields = List<Map<String, dynamic>>.from(docTypeDef['fields']);
        _metaFields.assignAll(rawFields);
        _parseLayout(rawFields);
      }
    } catch (e) {
      debugPrint("Warning: Could not fetch metadata for $doctype validation.");
    } finally {
      isMetaLoading.value = false;
    }
  }

  // FIX: Updated Parser to handle Sections AND Columns
  void _parseLayout(List<Map<String, dynamic>> rawFields) {
    List<FrappeFormSection> sections = [];

    // Temp holders
    String currentSectionLabel = "Details";
    List<FrappeFormColumn> currentSectionColumns = [];

    String currentColumnLabel = "";
    List<FrappeFieldConfig> currentColumnFields = [];

    void flushColumn() {
      if (currentColumnFields.isNotEmpty) {
        currentSectionColumns.add(
          FrappeFormColumn(
            label: currentColumnLabel,
            fields: List.from(currentColumnFields),
          ),
        );
        currentColumnFields = [];
        currentColumnLabel = "";
      }
    }

    void flushSection() {
      flushColumn(); // Ensure last column is added
      if (currentSectionColumns.isNotEmpty) {
        sections.add(
          FrappeFormSection(
            label: currentSectionLabel,
            columns: List.from(currentSectionColumns),
          ),
        );
        currentSectionColumns = [];
      }
    }

    for (var f in rawFields) {
      final String fieldtype = f['fieldtype'] ?? 'Data';
      final String label = f['label'] ?? '';
      final bool hidden = (f['hidden'] == 1);

      if (hidden) continue;

      // 1. SECTION BREAK
      if (fieldtype == 'Section Break') {
        flushSection();
        currentSectionLabel = label;
        continue;
      }

      // 2. COLUMN BREAK (New Logic)
      if (fieldtype == 'Column Break') {
        flushColumn();
        currentColumnLabel =
            label; // Set label for next group (ExpansionTile title)
        continue;
      }

      // 3. REGULAR FIELDS
      List<String>? optionsList;
      String? optionsLink;

      // Handle Options
      if (fieldtype == 'Select' && f['options'] != null) {
        optionsList = f['options'].toString().split('\n');
      } else if (['Link', 'Dynamic Link'].contains(fieldtype)) {
        optionsLink = f['options'];
      }

      final config = FrappeFieldConfig(
        label: label,
        fieldname: f['fieldname'] ?? '',
        fieldtype: fieldtype,
        reqd: (f['reqd'] == 1),
        readOnly: (f['read_only'] == 1),
        hidden: hidden,
        options: optionsList,
        optionsLink: optionsLink,
      );

      currentColumnFields.add(config);
    }

    // Add final section
    flushSection();

    layoutSections.assignAll(sections);
  }

  // ... (rest of initialise, setValue, getValue, load, save methods remain identical)
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
