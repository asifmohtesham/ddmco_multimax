import 'package:flutter/material.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';

// Import Field Widgets
import 'fields/basic_fields.dart';
import 'fields/link_field.dart';
import 'fields/child_table_field.dart';

class FrappeFieldFactory extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeFieldFactory({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // 1. LINK FIELDS
    if (config.fieldtype == 'Link' || config.fieldtype == 'Dynamic Link') {
      return FrappeLinkField(config: config, controller: controller);
    }

    // 2. CHILD TABLE
    if (config.fieldtype == 'Table') {
      return FrappeChildTableField(config: config, controller: controller);
    }

    // 3. BASIC FIELDS (Text, Select, Check, Date, etc.)
    // All handled by FrappeBasicField now
    if ([
      'Data',
      'Small Text',
      'Text',
      'Long Text',
      'Code',
      'Text Editor',
      'Select',
      'Check',
      'Date',
      'Time',
      'Datetime',
      'Int',
      'Float',
      'Currency',
      'Percent',
      'Password',
      'ReadOnly',
    ].contains(config.fieldtype)) {
      return FrappeBasicField(config: config, controller: controller);
    }

    // 4. UNSUPPORTED / HIDDEN / LAYOUT
    // Layout fields like Section Break are handled by the Form Renderer, not here.
    // Return empty for unsupported types to avoid crashes
    return const SizedBox.shrink();
  }
}
