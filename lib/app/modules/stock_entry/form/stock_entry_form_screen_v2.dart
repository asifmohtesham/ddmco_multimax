import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller_v2.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_table_field.dart';
import 'package:multimax/app/data/utils/frappe_logic_evaluator.dart';

class StockEntryFormScreenV2 extends GetView<StockEntryFormControllerV2> {
  const StockEntryFormScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await controller.confirmDiscard();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Obx(() => MainAppBar(
            title: controller.doc['name'] ?? 'New Stock Entry',
            status: controller.doc['status'],
            isDirty: controller.isDirty,
            isSaving: controller.isSaving.value,
            // Check docstatus to disable save on submitted documents
            onSave: controller.doc['docstatus'] == 1 ? null : controller.save,
          )),
        ),
        body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return SafeArea(child: _buildDynamicForm());
        }),
      ),
    );
  }

  Widget _buildDynamicForm() {
    final hasTabs = controller.metaFields.any(
      (f) => f['fieldtype'] == 'Tab Break',
    );
    if (hasTabs) {
      return _buildTabbedLayout();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: _buildSectionWidgets(controller.metaFields)),
    );
  }

  Widget _buildTabbedLayout() {
    List<Map<String, dynamic>> tabs = [];
    List<dynamic> buffer = [];
    String currentLabel = 'Details';

    for (var field in controller.metaFields) {
      if (field['fieldtype'] == 'Tab Break') {
        if (buffer.isNotEmpty) {
          tabs.add({'label': currentLabel, 'fields': List.from(buffer)});
        }
        buffer = [];
        currentLabel = field['label'] ?? 'Tab';
      } else {
        buffer.add(field);
      }
    }
    if (buffer.isNotEmpty) {
      tabs.add({'label': currentLabel, 'fields': buffer});
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: Colors.blue[900],
            indicatorColor: Colors.blue[900],
            unselectedLabelColor: Colors.black87,
            tabs: tabs.map((t) => Tab(text: t['label'])).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: tabs
                  .map(
                    (t) => SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: _buildSectionWidgets(t['fields']),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSectionWidgets(List<dynamic> fields) {
    List<Widget> sections = [];
    List<dynamic> currentFields = [];
    String? sectionLabel;

    void flush() {
      if (currentFields.isNotEmpty) {
        sections.add(_buildSectionCard(sectionLabel, currentFields));
        currentFields = [];
        sectionLabel = null;
      }
    }

    for (var field in fields) {
      if (field['fieldtype'] == 'Section Break') {
        flush();
        sectionLabel = field['label'];
      } else if (field['fieldtype'] == 'Column Break') {
        continue;
      } else {
        // --- LOGIC: Filter visible fields here before grouping them ---
        bool isVisible = true;
        if (field['depends_on'] != null) {
          isVisible = FrappeLogicEvaluator.evaluate(
              field['depends_on'].toString(),
              controller.doc
          );
        }

        if (field['hidden'] == 1) isVisible = false;

        if (isVisible) {
          currentFields.add(field);
        }
      }
    }
    flush();
    return sections;
  }

  Widget _buildSectionCard(String? title, List<dynamic> fields) {
    if (fields.isEmpty) return const SizedBox.shrink();
    if (title == null) {
      return Column(children: fields.map(_buildField).toList());
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: LinearBorder.none,
        collapsedShape: LinearBorder.none,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.all(12),
        children: fields.map(_buildField).toList(),
      ),
    );
  }

  Widget _buildField(dynamic fieldMeta) {
    // Hidden fields already filtered out in sections, but check 'depends_on' again
    // just in case direct access happens, or for reactive re-evaluation safety inside sections.
    // However, since sections are rebuilt on doc change (Obx at root), simple render is okay.

    // 1. Logic: Check Mandatory Depends On
    bool isMandatory = fieldMeta['reqd'] == 1;
    if (fieldMeta['mandatory_depends_on'] != null) {
      bool cond = FrappeLogicEvaluator.evaluate(
          fieldMeta['mandatory_depends_on'].toString(),
          controller.doc
      );
      if (cond) isMandatory = true;
    }

    // Clone meta to modify reqd status
    final effectiveMeta = Map<String, dynamic>.from(fieldMeta);
    effectiveMeta['reqd'] = isMandatory ? 1 : 0;

    // --- Special Handling: Scan Barcode ---
    if (effectiveMeta['fieldname'] == 'scan_barcode') {
      effectiveMeta['fieldtype'] = 'Barcode'; // Force type
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: FrappeFieldWidget(
          fieldMeta: effectiveMeta,
          doc: controller.doc,
          value: controller.doc['scan_barcode'],
          textController: controller.scanBarcodeController,
          onChanged: (val) => controller.updateField('scan_barcode', val),
          onSubmitted: (val) => controller.processBarcodeScan(val.toString()),
        ),
      );
    }

    // --- Table Fields ---
    if (effectiveMeta['fieldtype'] == 'Table') {
      // The options field usually contains the Child DocType name (e.g., "Stock Entry Detail")
      final childDocType = effectiveMeta['options'];
      // Retrieve the whitelist-filtered meta for this Child DocType
      List<Map<String, dynamic>>? childMeta =
          controller.childMetaMap[childDocType];

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FrappeTableField(
          label: effectiveMeta['label'] ?? '',
          items: controller.getItems(),
          fieldMeta: effectiveMeta,
          childFieldMeta: childMeta,

          // Pass the parent document for 'eval:parent.field' logic
          parentDoc: controller.doc,
          // Pass the whitelist here
          onRowUpdate: (i, data) => controller.updateRow(i, data),
          // --- Enabled Add/Delete Actions ---
          onAddRow: (data) => controller.addRow(data),
          onDeleteRow: (i) => controller.removeRow(i),

          // --- Filter Logic ---
          onGetFilters: (fieldname, row) {
            // Apply Batch No Filter based on Item Code
            if (fieldname == 'batch_no') {
              if (row['item_code'] != null && row['item_code'].isNotEmpty) {
                return {'item': row['item_code']};
              }
            }
            return {};
          },

          onRowFieldChange: (key, value, row) {
            if (key == 'batch_no') {
              if (value != null && value.toString().isNotEmpty) {
                row['use_serial_batch_fields'] = 1;
              }
            } else if (key == 'serial_and_batch_bundle') {
              if (value != null && value.toString().isNotEmpty) {
                row['use_serial_batch_fields'] = 0;
              }
            }
          },
        ),
      );
    }

    // --- Standard Fields ---
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: FrappeFieldWidget(
        fieldMeta: effectiveMeta,
        doc: controller.doc,
        value: controller.doc[effectiveMeta['fieldname']],
        onChanged: (val) => controller.updateField(effectiveMeta['fieldname'], val),
      ),
    );
  }
}