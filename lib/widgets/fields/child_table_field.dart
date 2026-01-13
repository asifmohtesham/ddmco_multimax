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
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(config.label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: FrappeTheme.textLabel, letterSpacing: 1.0)),
            if (!config.readOnly)
              TextButton.icon(
                onPressed: () => _openRowEditor(context, null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text("Add"),
                style: TextButton.styleFrom(foregroundColor: FrappeTheme.primary),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Obx(() {
          final List<dynamic> rows = controller.getValue<List>(config.fieldname) ?? [];

          if (rows.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(FrappeTheme.radius),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text("No items", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (c, i) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index] as Map<String, dynamic>;
              return _buildRowCard(context, row, index);
            },
          );
        }),
        const SizedBox(height: FrappeTheme.spacing),
      ],
    );
  }

  Widget _buildRowCard(BuildContext context, Map<String, dynamic> row, int index) {
    String title = "Row $index";
    String subtitle = "";
    String trailing = "";

    if (config.childFields != null) {
      final listFields = config.childFields!.where((f) => f.inListView).toList();
      if (listFields.isNotEmpty) title = "${row[listFields[0].fieldname] ?? '-'}";
      if (listFields.length > 1) subtitle = "${listFields[1].label}: ${row[listFields[1].fieldname] ?? '-'}";
      final amountField = config.childFields!.firstWhereOrNull((f) => ['Currency', 'Float'].contains(f.fieldtype));
      if (amountField != null) trailing = "${row[amountField.fieldname] ?? ''}";
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        onTap: () => _openRowEditor(context, row, index: index),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: FrappeTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description_outlined, color: FrappeTheme.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              if (trailing.isNotEmpty) Text(trailing, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _openRowEditor(BuildContext context, Map<String, dynamic>? rowData, {int? index}) {
    final String rowControllerTag = "row_${DateTime.now().millisecondsSinceEpoch}";

    // Create temporary controller
    final rowController = Get.put(FrappeFormController(doctype: "Child Row"), tag: rowControllerTag);
    rowController.initialize(rowData);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: FrappeTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(rowData == null ? "Add Item" : "Edit Item", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        // Save back to main controller
                        final updatedRow = rowController.data;
                        final currentList = List<Map<String, dynamic>>.from(controller.getValue<List>(config.fieldname) ?? []);

                        if (index != null) {
                          currentList[index] = updatedRow;
                        } else {
                          currentList.add(updatedRow);
                        }

                        controller.setValue(config.fieldname, currentList);
                        Navigator.pop(context);
                      },
                      child: const Text("Done"),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: (config.childFields ?? []).map((field) {
                    // CRITICAL: We pass the TEMPORARY rowController to the fields here
                    return FrappeFieldFactory(config: field, controller: rowController);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      Get.delete<FrappeFormController>(tag: rowControllerTag);
    });
  }
}