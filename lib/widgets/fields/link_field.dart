import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';

class FrappeLinkField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeLinkField({
    super.key,
    required this.config,
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FrappeTheme.spacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Autocomplete<String>(
            // Safely access the controller passed in constructor
            initialValue: TextEditingValue(text: controller.getValue<String>(config.fieldname) ?? ""),

            optionsBuilder: (TextEditingValue textEditingValue) {
              return controller.searchLink(config.optionsLink ?? "", textEditingValue.text);
            },

            onSelected: (String selection) {
              controller.setValue(config.fieldname, selection);
            },

            fieldViewBuilder: (context, textController, focusNode, onEditingComplete) {
              // Note: If you need to sync external updates to this field while open,
              // you would need a StatefulWidget or a GetX Worker here.
              // For now, initialValue handles the display.

              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                decoration: FrappeTheme.inputDecoration(config.label).copyWith(
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
              );
            },
          );
        },
      ),
    );
  }
}