import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';
import '../frappe_field_factory.dart';

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
          // --- Header ---
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
              // Optional: Add Row Button (can be implemented later)
              // if (!config.readOnly) Icon(Icons.add, color: FrappeTheme.primary),
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
              ),
              child: const Text(
                "No items",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),

          // --- Rows List ---
          if (rows.isNotEmpty)
            // Replaced ListView with Column to prevent Scrollable PageStorage collisions
            // Since physics is NeverScrollable, a Column is more efficient and safer.
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
  ) {
    // 1. Determine Title & Subtitle from configured fields
    String title = "Row #${index + 1}";
    String subtitle = "";
    String trailing = "";

    // Iterate child fields to find suitable display columns
    if (config.childFields != null) {
      for (var f in config.childFields!) {
        final val = row[f.fieldname]?.toString() ?? '';
        if (val.isEmpty) continue;

        // Use first Link or Data field as title if generic
        if (title.startsWith("Row #") &&
            (f.fieldtype == 'Link' || f.fieldtype == 'Data')) {
          title = val;
        }
        // Use others as subtitle
        else if (subtitle.length < 30 && f.inListView) {
          if (subtitle.isNotEmpty) subtitle += " • ";
          subtitle += "${f.label}: $val";
        }
        // Use Currency/Float as trailing
        else if (trailing.isEmpty &&
            (f.fieldtype == 'Currency' || f.fieldtype == 'Float')) {
          trailing = val;
        }
      }
    }

    return InkWell(
      onTap: () {
        // Handle Row Edit (Future implementation)
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
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
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Text(
                trailing,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
