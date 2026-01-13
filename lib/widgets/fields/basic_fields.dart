import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';

class FrappeTextField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;
  final int maxLines;

  const FrappeTextField({
    super.key,
    required this.config,
    required this.controller,
    this.maxLines = 1
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FrappeTheme.spacing),
      child: Obx(() {
        // FIX: Handle mixed types (int/double from API, String from input)
        final rawValue = controller.getValue(config.fieldname);
        final String? displayValue = rawValue?.toString();

        return TextFormField(
          // Key ensures the field updates if the underlying data changes externally
          key: ValueKey(displayValue),
          initialValue: displayValue,
          readOnly: config.readOnly,
          maxLines: maxLines,
          keyboardType: ['Int', 'Float', 'Currency'].contains(config.fieldtype)
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: FrappeTheme.inputDecoration(config.label).copyWith(
            suffixIcon: config.reqd ? const Icon(Icons.star, size: 8, color: Colors.red) : null,
          ),
          onChanged: (val) => controller.setValue(config.fieldname, val),
        );
      }),
    );
  }
}

class FrappeSelectField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeSelectField({
    super.key,
    required this.config,
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FrappeTheme.spacing),
      child: Obx(() {
        final val = controller.getValue<String>(config.fieldname);
        // Ensure the value exists in options, otherwise null (to avoid dropdown crash)
        final validVal = (config.options != null && config.options!.contains(val)) ? val : null;

        return DropdownButtonFormField<String>(
          value: validVal,
          decoration: FrappeTheme.inputDecoration(config.label),
          items: (config.options ?? []).map((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value));
          }).toList(),
          onChanged: config.readOnly ? null : (val) => controller.setValue(config.fieldname, val),
        );
      }),
    );
  }
}

class FrappeCheckField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeCheckField({
    super.key,
    required this.config,
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FrappeTheme.spacing),
      child: Obx(() {
        final val = controller.getValue(config.fieldname);
        final bool isChecked = val == 1 || val == true || val == "1";

        return SwitchListTile.adaptive(
          title: Text(config.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          value: isChecked,
          contentPadding: EdgeInsets.zero,
          activeColor: FrappeTheme.primary,
          onChanged: config.readOnly ? null : (bool val) => controller.setValue(config.fieldname, val ? 1 : 0),
        );
      }),
    );
  }
}

class FrappeDateField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeDateField({
    super.key,
    required this.config,
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FrappeTheme.spacing),
      child: GestureDetector(
        onTap: config.readOnly ? null : () async {
          DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            controller.setValue(config.fieldname, DateFormat('yyyy-MM-dd').format(picked));
          }
        },
        child: AbsorbPointer(
          child: Obx(() {
            final val = controller.getValue(config.fieldname)?.toString();
            return TextFormField(
              key: ValueKey(val),
              initialValue: val,
              decoration: FrappeTheme.inputDecoration(config.label).copyWith(
                suffixIcon: const Icon(Icons.calendar_today, size: 18),
              ),
            );
          }),
        ),
      ),
    );
  }
}