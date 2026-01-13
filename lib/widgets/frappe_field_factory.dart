import 'package:flutter/material.dart';
import '../models/frappe_field_config.dart';
import '../controllers/frappe_form_controller.dart';
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
    if (config.hidden) return const SizedBox.shrink();

    switch (config.fieldtype) {
      case 'Data':
      case 'Int':
      case 'Float':
      case 'Currency':
      case 'Password':
        return FrappeTextField(config: config, controller: controller);

      case 'Small Text':
      case 'Text':
      case 'Long Text':
        return FrappeTextField(config: config, controller: controller, maxLines: 4);

      case 'Select':
        return FrappeSelectField(config: config, controller: controller);

      case 'Check':
        return FrappeCheckField(config: config, controller: controller);

      case 'Date':
      case 'Datetime':
        return FrappeDateField(config: config, controller: controller);

      case 'Link':
        return FrappeLinkField(config: config, controller: controller);

      case 'Table':
        return FrappeChildTableField(config: config, controller: controller);

      default:
        return const SizedBox.shrink();
    }
  }
}