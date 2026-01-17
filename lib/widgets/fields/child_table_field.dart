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
      List<Widget> fieldWidgets = [];

      // 1. Identify fields to display (Priority: in_list_view > search_fields > fallback)
      List<FrappeFieldConfig> visibleFields = tableController.childFields
          .where((f) => f.inListView)
          .toList();

      // Fallback: If no metadata loaded yet or no in_list_view fields, use search_fields
      if (visibleFields.isEmpty && tableController.searchFields.isNotEmpty) {
        visibleFields = tableController.searchFields
            .map(
              (fname) => FrappeFieldConfig(
                label: fname,
                fieldname: fname,
                fieldtype: 'Data',
              ),
            )
            .toList();
      }

      // 2. Build Vertical List of Fields
      if (visibleFields.isNotEmpty) {
        for (int i = 0; i < visibleFields.length; i++) {
          final f = visibleFields[i];
          final val = row[f.fieldname]?.toString();

          if (val != null && val.isNotEmpty) {
            // First item: Bold Title style
            if (i == 0) {
              fieldWidgets.add(
                Text(
                  val,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: FrappeTheme.textBody,
                  ),
                ),
              );
            }
            // Subsequent items: Label: Value style
            else {
              fieldWidgets.add(
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${f.label}: ",
                        style: const TextStyle(
                          fontSize: 12,
                          color: FrappeTheme.textLabel,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          val,
                          style: const TextStyle(
                            fontSize: 12,
                            color: FrappeTheme.textBody,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
        }
      }

      // Fallback if no data fields found at all
      if (fieldWidgets.isEmpty) {
        fieldWidgets.add(
          Text(
            "Row #${index + 1}",
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        );
      }

      return InkWell(
        onTap: config.readOnly
            ? null
            : () => _openRowEditor(context, row, index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: fieldWidgets,
                ),
              ),
              if (!config.readOnly)
                const Padding(
                  padding: EdgeInsets.only(left: 12.0, top: 2.0),
                  child: Icon(
                    Icons.edit,
                    size: 16,
                    color: FrappeTheme.textLabel,
                  ),
                ),
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
    final String? childDocType = config.optionsLink;

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
            rows.add(updatedRow);
          } else {
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
