import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ConfigureColumnsController extends GetxController {
  final List<Map<String, dynamic>> allFields;
  final Function(List<String>) onSave;

  // Use a simple List and GetBuilder for manual update control
  List<String> selectedFields = [];

  ConfigureColumnsController({
    required this.allFields,
    required List<String> currentVisibleFields,
    required this.onSave,
  }) {
    // Initialize with a copy of currently visible fields
    selectedFields = List.from(currentVisibleFields);
  }

  void toggleField(String fieldname, bool? isChecked) {
    if (isChecked == true) {
      if (!selectedFields.contains(fieldname)) {
        selectedFields.add(fieldname);
      }
    } else {
      selectedFields.remove(fieldname);
    }
    // Manually trigger a rebuild of the GetBuilder
    update();
  }

  void save() {
    onSave(selectedFields);
    Get.back();
  }
}

class ConfigureColumnsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> allFields;
  final List<String> currentVisibleFields;
  final Function(List<String>) onSave;

  const ConfigureColumnsSheet({
    super.key,
    required this.allFields,
    required this.currentVisibleFields,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a unique tag to ensure a fresh controller for every sheet instance
    final String uniqueTag =
        'config_columns_${DateTime.now().millisecondsSinceEpoch}';

    return GetBuilder<ConfigureColumnsController>(
      init: ConfigureColumnsController(
        allFields: allFields,
        currentVisibleFields: currentVisibleFields,
        onSave: onSave,
      ),
      tag: uniqueTag,
      builder: (controller) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Header ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Configure Columns",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const Divider(),

                // --- Field List ---
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: allFields.length,
                    itemBuilder: (context, index) {
                      final field = allFields[index];
                      final String fieldname = field['fieldname'];
                      final String label = field['label'] ?? fieldname;

                      // Skip hidden fields
                      if (field['hidden'] == 1) return const SizedBox.shrink();

                      final isSelected = controller.selectedFields.contains(
                        fieldname,
                      );

                      return CheckboxListTile(
                        title: Text(label),
                        value: isSelected,
                        activeColor: Theme.of(context).primaryColor,
                        // Pass logic to controller
                        onChanged: (val) =>
                            controller.toggleField(fieldname, val),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // --- Save Button ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Apply Changes"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
