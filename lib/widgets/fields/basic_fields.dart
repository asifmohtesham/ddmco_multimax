import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';

// --- 1. TEXT FIELD (Data, Int, Float, Small Text) ---
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
    return Obx(() {
      final val = controller.data[config.fieldname];

      // Handle numeric conversion safely
      String initialValue = '';
      if (val != null) {
        initialValue = val.toString();
      }

      return TextFormField(
        // Key forces rebuild if fieldname changes (rare) or form resets
        key: ValueKey('${config.fieldname}_$initialValue'),
        initialValue: initialValue,
        readOnly: config.readOnly,
        keyboardType: _getKeyboardType(),
        decoration: FrappeTheme.inputDecoration(config.label).copyWith(
          filled: config.readOnly,
          fillColor: config.readOnly ? FrappeTheme.surface : Colors.white,
        ),
        onChanged: (value) {
          if (config.fieldtype == 'Int') {
            controller.setValue(config.fieldname, int.tryParse(value));
          } else if (config.fieldtype == 'Float' ||
              config.fieldtype == 'Currency') {
            controller.setValue(config.fieldname, double.tryParse(value));
          } else {
            controller.setValue(config.fieldname, value);
          }
        },
        validator: (val) {
          if (config.reqd && (val == null || val.isEmpty)) {
            return '${config.label} is required';
          }
          return null;
        },
      );
    });
  }

  TextInputType _getKeyboardType() {
    if (config.fieldtype == 'Int' ||
        config.fieldtype == 'Float' ||
        config.fieldtype == 'Currency') {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    if (config.fieldtype == 'Small Text' || config.fieldtype == 'Text') {
      return TextInputType.multiline;
    }
    return TextInputType.text;
  }
}

// --- 2. CHECKBOX (Check) ---
class FrappeCheckField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeCheckField({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final val = controller.data[config.fieldname];
      final bool isChecked = (val == 1 || val == true);

      return FormField<bool>(
        initialValue: isChecked,
        builder: (state) {
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              config.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            value: isChecked,
            onChanged: config.readOnly
                ? null
                : (v) {
                    controller.setValue(config.fieldname, v ? 1 : 0);
                  },
            activeColor: FrappeTheme.primary,
          );
        },
      );
    });
  }
}

// --- 3. SELECT DROPDOWN (Select) ---
class FrappeSelectField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeSelectField({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final val = controller.data[config.fieldname]?.toString();
      final options = config.options ?? [];

      return DropdownButtonFormField<String>(
        value: (val != null && options.contains(val)) ? val : null,
        decoration: FrappeTheme.inputDecoration(config.label).copyWith(
          filled: config.readOnly,
          fillColor: config.readOnly ? FrappeTheme.surface : Colors.white,
        ),
        // FIX: Add isExpanded to prevent overflow
        isExpanded: true,
        items: options.map((opt) {
          return DropdownMenuItem<String>(
            value: opt,
            child: Text(
              opt,
              overflow: TextOverflow.ellipsis,
              // Ensure text truncates if still too long
              maxLines: 1,
            ),
          );
        }).toList(),
        onChanged: config.readOnly
            ? null
            : (newValue) {
                controller.setValue(config.fieldname, newValue);
              },
        validator: (val) {
          if (config.reqd && (val == null || val.isEmpty)) {
            return 'Please select ${config.label}';
          }
          return null;
        },
      );
    });
  }
}

// --- 4. DATE PICKER (Date) ---
class FrappeDateField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeDateField({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final val = controller.data[config.fieldname];
      String display = '';
      if (val != null) {
        display = val.toString();
      }

      return InkWell(
        onTap: config.readOnly
            ? null
            : () async {
                DateTime initial = DateTime.now();
                if (val != null && val.toString().isNotEmpty) {
                  try {
                    initial = DateTime.parse(val.toString());
                  } catch (_) {}
                }

                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: FrappeTheme.primary,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  final formatted = DateFormat('yyyy-MM-dd').format(picked);
                  controller.setValue(config.fieldname, formatted);
                }
              },
        child: InputDecorator(
          decoration: FrappeTheme.inputDecoration(config.label).copyWith(
            suffixIcon: const Icon(Icons.calendar_today, size: 20),
            filled: config.readOnly,
            fillColor: config.readOnly ? FrappeTheme.surface : Colors.white,
          ),
          child: Text(
            display.isEmpty ? 'YYYY-MM-DD' : display,
            style: TextStyle(
              color: display.isEmpty ? Colors.grey : FrappeTheme.textBody,
            ),
          ),
        ),
      );
    });
  }
}
