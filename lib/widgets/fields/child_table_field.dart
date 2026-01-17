import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';
import 'child_table_input_sheet.dart'; // Import the new sheet

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
            ListView.separated(
              key: ValueKey('${config.fieldname}_${rows.length}'),
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (c, i) =>
                  const Divider(height: 16, thickness: 0.5),
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row is! Map) return const SizedBox.shrink();

                return _buildRowCard(
                  context,
                  Map<String, dynamic>.from(row),
                  index,
                );
              },
            ),
        ],
      );
    });
  }

  Widget _buildRowCard(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
  ) {
    // 1. Determine Title & Subtitle from configured fields
    String title = "Row #${index + 1}";
    String subtitle = "";
    String trailing = "";

    // Intelligent Title/Subtitle generation based on field types
    if (config.childFields != null) {
      for (var f in config.childFields!) {
        final val = row[f.fieldname]?.toString() ?? '';
        if (val.isEmpty) continue;

        // Use first Link or Data field as title if generic
        if (title.startsWith("Row #") &&
            (f.fieldtype == 'Link' || f.fieldtype == 'Data')) {
          title = val;
        } else if (subtitle.length < 40 && f.inListView) {
          if (subtitle.isNotEmpty) subtitle += " • ";
          subtitle += "${f.label}: $val";
        } else if (trailing.isEmpty &&
            (f.fieldtype == 'Currency' ||
                f.fieldtype == 'Float' ||
                f.fieldtype == 'Int')) {
          trailing = val;
        }
      }
    }

    return InkWell(
      onTap: config.readOnly ? null : () => _openRowEditor(context, row, index),
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
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: FrappeTheme.textLabel,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
