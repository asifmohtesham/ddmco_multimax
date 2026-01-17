import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';
import 'child_table_input_sheet.dart';

class FrappeChildTableField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeChildTableField({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // Unique tag to ensure one controller per field instance
    final tag = '${controller.doctype}_${config.fieldname}_table';

    final tableController = Get.put(
      FrappeChildTableController(
        parentController: controller,
        childDoctype: config.optionsLink,
      ),
      tag: tag,
    );

    return Obx(() {
      // Safely cast the list
      final rawVal = controller.data[config.fieldname];
      final List rows = (rawVal is List) ? rawVal : [];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header with Add Button ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                config.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: FrappeTheme.textLabel,
                ),
              ),
              if (!config.readOnly)
                InkWell(
                  onTap: () => _openRowEditor(context, null, -1),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.add_circle_outline,
                          color: FrappeTheme.primary,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          "Add",
                          style: TextStyle(
                            color: FrappeTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // --- Empty State ---
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FrappeTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FrappeTheme.border),
              ),
              child: const Center(
                child: Text(
                  "No items added yet",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),

          // --- Rows List ---
          if (rows.isNotEmpty)
            Column(
              children: List.generate(rows.length, (index) {
                final row = rows[index];
                if (row is! Map) return const SizedBox.shrink();

                return Column(
                  children: [
                    _buildRowCard(
                      context,
                      Map<String, dynamic>.from(row),
                      index,
                      tableController,
                    ),
                    if (index < rows.length - 1)
                      const Divider(height: 16, thickness: 0.5),
                  ],
                );
              }),
            ),
        ],
      );
    });
  }

  Widget _buildRowCard(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
    FrappeChildTableController tableController,
  ) {
    return Obx(() {
      String title = "Row #${index + 1}";
      String subtitle = "";
      String trailing = "";

      // 1. DETERMINE TITLE
      // Priority 1: 'search_fields' from metadata
      if (tableController.searchFields.isNotEmpty) {
        List<String> parts = [];
        for (var field in tableController.searchFields) {
          final val = row[field]?.toString();
          if (val != null && val.isNotEmpty) parts.add(val);
        }
        if (parts.isNotEmpty) title = parts.join(", ");
      }
      // Priority 2: 'title_field' from metadata
      else if (tableController.titleField.value.isNotEmpty) {
        final val = row[tableController.titleField.value]?.toString();
        if (val != null && val.isNotEmpty) title = val;
      }
      // Priority 3: First Link/Data field found in loaded definitions
      else if (tableController.childFields.isNotEmpty) {
        for (var f in tableController.childFields) {
          if (f.fieldtype == 'Link' || f.fieldtype == 'Data') {
            final val = row[f.fieldname]?.toString();
            if (val != null && val.isNotEmpty) {
              title = val;
              break;
            }
          }
        }
      }

      // 2. DETERMINE SUBTITLE & TRAILING
      // We need the field definitions to know what to show
      if (tableController.childFields.isNotEmpty) {
        for (var f in tableController.childFields) {
          final val = row[f.fieldname]?.toString() ?? '';
          if (val.isEmpty) continue;

          // Don't repeat the title in the subtitle
          if (title.contains(val)) continue;

          // Trailing: Amount or Qty
          if (trailing.isEmpty &&
              (f.fieldtype == 'Currency' ||
                  f.fieldtype == 'Float' ||
                  f.fieldtype == 'Int')) {
            // Simple heuristic: if label contains Amount, Total, Qty
            if (f.label.contains("Amount") ||
                f.label.contains("Total") ||
                f.label.contains("Qty")) {
              trailing = val;
              continue;
            }
          }

          // Subtitle: Fields marked as in_list_view
          if (f.inListView && subtitle.length < 60) {
            if (subtitle.isNotEmpty) subtitle += " • ";
            subtitle += "${f.label}: $val";
          }
        }
      }

      return InkWell(
        onTap: config.readOnly
            ? null
            : () => _openRowEditor(context, row, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: FrappeTheme.textBody,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: FrappeTheme.textLabel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FrappeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trailing,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (!config.readOnly)
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      );
    });
  }

  void _openRowEditor(
    BuildContext context,
    Map<String, dynamic>? currentRow,
    int index,
  ) {
    final String? childDocType =
        config.optionsLink; // Table field options = Child DocType Name

    if (childDocType == null || childDocType.isEmpty) {
      Get.snackbar("Error", "Child DocType not configured for ${config.label}");
      return;
    }

    Get.bottomSheet(
      ChildTableInputSheet(
        childDoctype: childDocType,
        initialData: currentRow,
        onSave: (updatedRow) {
          final List rows = List.from(controller.data[config.fieldname] ?? []);

          if (index == -1) {
            // Add New
            rows.add(updatedRow);
          } else {
            // Edit Existing
            rows[index] = updatedRow;
          }
          controller.setValue(config.fieldname, rows);
        },
        onDelete: (index != -1)
            ? () {
                final List rows = List.from(
                  controller.data[config.fieldname] ?? [],
                );
                rows.removeAt(index);
                controller.setValue(config.fieldname, rows);
              }
            : null,
      ),
      isScrollControlled: true,
      ignoreSafeArea: false,
    );
  }
}

class FrappeChildTableController extends GetxController {
  final FrappeFormController parentController;
  final String? childDoctype;

  final RxList<String> searchFields = <String>[].obs;
  final RxString titleField = ''.obs;
  final RxList<FrappeFieldConfig> childFields = <FrappeFieldConfig>[].obs;

  FrappeChildTableController({
    required this.parentController,
    required this.childDoctype,
  });

  @override
  void onInit() {
    super.onInit();
    if (childDoctype != null) {
      _fetchMetadata();
    }
  }

  Future<void> _fetchMetadata() async {
    try {
      final meta = await parentController.api.getDocType(childDoctype!);

      // 1. Parse Search Fields
      if (meta['search_fields'] != null) {
        final fieldsStr = meta['search_fields'].toString();
        if (fieldsStr.isNotEmpty) {
          searchFields.assignAll(
            fieldsStr.split(',').map((e) => e.trim()).toList(),
          );
        }
      }

      // 2. Parse Title Field
      if (meta['title_field'] != null) {
        titleField.value = meta['title_field'].toString();
      }

      // 3. Parse Field Definitions (Columns)
      if (meta['fields'] != null) {
        final rawFields = List<Map<String, dynamic>>.from(meta['fields']);
        final parsed = rawFields
            .map(
              (f) => FrappeFieldConfig(
                label: f['label'] ?? '',
                fieldname: f['fieldname'] ?? '',
                fieldtype: f['fieldtype'] ?? 'Data',
                inListView: (f['in_list_view'] == 1),
                reqd: (f['reqd'] == 1),
                readOnly: (f['read_only'] == 1),
                hidden: (f['hidden'] == 1),
              ),
            )
            .toList();
        childFields.assignAll(parsed);
      }
    } catch (e) {
      debugPrint("Failed to fetch child meta for $childDoctype: $e");
    }
  }
}
