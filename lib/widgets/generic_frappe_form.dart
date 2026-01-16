import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/theme/frappe_theme.dart';

class GenericFrappeForm extends StatelessWidget {
  final FrappeFormController controller;

  const GenericFrappeForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isMetaLoading.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (controller.layoutSections.isEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        children: controller.layoutSections.map((section) {
          return _buildSection(section);
        }).toList(),
      );
    });
  }

  Widget _buildSection(section) {
    // Only render section if it has fields
    if (section.fields.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Label
          if (section.label.isNotEmpty) ...[
            Text(
              section.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: FrappeTheme.textLabel,
                letterSpacing: 0.5,
              ),
            ),
            const Divider(height: 24),
          ],

          // Fields List
          ...section.fields.map<Widget>((fieldConfig) {
            // Handle unsupported types gracefully by skipping or rendering basic text
            if ([
              'Table',
              'HTML',
              'Button',
              'Signature',
            ].contains(fieldConfig.fieldtype)) {
              return const SizedBox.shrink(); // Skip complex types in auto-builder for now
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: FrappeFieldFactory(
                config: fieldConfig,
                controller: controller,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
