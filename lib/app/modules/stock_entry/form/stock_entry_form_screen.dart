import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/widgets/frappe_form_layout.dart';
import 'package:multimax/widgets/generic_frappe_form.dart';

class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isReadOnly = controller.isSubmitted;
      // Show loading only if data is empty and we aren't creating a new one
      final isLoading = controller.data.isEmpty && controller.name != 'New Stock Entry';

      return FrappeFormLayout(
        title: controller.name,
        isLoading: isLoading,
        // Disable save button if document is submitted
        onSave: isReadOnly ? null : controller.save,

        body: SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // This single line renders the entire metadata-driven form
              GenericFrappeForm(controller: controller),

              const SizedBox(height: 80), // Padding for sticky footer
            ],
          ),
        ),
      );
    });
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FrappeTheme.textLabel,
              letterSpacing: 0.5,
            ),
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }
}