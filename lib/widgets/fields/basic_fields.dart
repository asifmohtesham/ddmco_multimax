import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../models/frappe_field_config.dart';
import '../../controllers/frappe_form_controller.dart';
import '../../theme/frappe_theme.dart';

class FrappeBasicField extends StatelessWidget {
  final FrappeFieldConfig config;
  final FrappeFormController controller;

  const FrappeBasicField({
    super.key,
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // Initialise controller logic
    final fieldController = Get.put(
      FrappeBasicFieldController(config: config, formController: controller),
      tag: '${controller.doctype}_${config.fieldname}',
    );

    final isReadOnly = config.readOnly;

    // 1. CHECKBOX
    if (config.fieldtype == 'Check') {
      return Obx(() {
        final val = controller.data[config.fieldname];
        final bool isChecked = (val == 1 || val == true || val == '1');

        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            config.label,
            style: const TextStyle(fontSize: 14, color: FrappeTheme.textBody),
          ),
          value: isChecked,
          onChanged: isReadOnly
              ? null
              : (bool? value) {
                  controller.setValue(
                    config.fieldname,
                    (value == true) ? 1 : 0,
                  );
                },
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: FrappeTheme.primary,
        );
      });
    }

    // 2. SELECT (DROPDOWN)
    if (config.fieldtype == 'Select') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final val = controller.data[config.fieldname]?.toString();
            return DropdownButtonFormField<String>(
              value: (config.options?.contains(val) ?? false) ? val : null,
              decoration: FrappeTheme.inputDecoration(config.label).copyWith(
                fillColor: isReadOnly ? FrappeTheme.surface : Colors.white,
              ),
              items:
                  config.options?.map((opt) {
                    return DropdownMenuItem(
                      value: opt,
                      child: Text(opt, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList() ??
                  [],
              onChanged: isReadOnly
                  ? null
                  : (newVal) {
                      if (newVal != null)
                        controller.setValue(config.fieldname, newVal);
                    },
              validator: (val) {
                if (config.reqd &&
                    !isReadOnly &&
                    (val == null || val.isEmpty)) {
                  return '${config.label} is required';
                }
                return null;
              },
            );
          }),
        ],
      );
    }

    // 3. TEXT / NUMBER / DATE INPUTS
    TextInputType keyboardType = TextInputType.text;
    List<TextInputFormatter> formatters = [];

    if (['Int'].contains(config.fieldtype)) {
      keyboardType = const TextInputType.numberWithOptions(signed: true);
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    } else if (['Float', 'Currency', 'Percent'].contains(config.fieldtype)) {
      keyboardType = const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      );
      formatters.add(FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')));
    }

    // Handle Tap for Date/Time
    VoidCallback? onTap;
    if (!isReadOnly) {
      if (config.fieldtype == 'Date')
        onTap = () => fieldController.pickDate(context);
      if (config.fieldtype == 'Time')
        onTap = () => fieldController.pickTime(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: fieldController.textEditingController,
          readOnly:
              isReadOnly ||
              ['Date', 'Time', 'Datetime'].contains(config.fieldtype),
          onTap: onTap,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          maxLines:
              ['Small Text', 'Text', 'Long Text'].contains(config.fieldtype)
              ? 3
              : 1,
          style: const TextStyle(fontSize: 14, color: FrappeTheme.textBody),
          decoration: FrappeTheme.inputDecoration(config.label).copyWith(
            fillColor: isReadOnly ? FrappeTheme.surface : Colors.white,
            suffixIcon: _buildSuffixIcon(config),
          ),
          onChanged: fieldController.onUserChanged,
          validator: (val) {
            if (config.reqd && !isReadOnly && (val == null || val.isEmpty)) {
              return '${config.label} is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget? _buildSuffixIcon(FrappeFieldConfig field) {
    if (field.fieldtype == 'Date')
      return const Icon(Icons.calendar_today, size: 20);
    if (field.fieldtype == 'Time')
      return const Icon(Icons.access_time, size: 20);
    return null;
  }
}

class FrappeBasicFieldController extends GetxController {
  final FrappeFieldConfig config;
  final FrappeFormController formController;

  late TextEditingController textEditingController;
  Worker? _worker;

  FrappeBasicFieldController({
    required this.config,
    required this.formController,
  });

  @override
  void onInit() {
    super.onInit();
    final initialVal = _getSafeValue(formController.data[config.fieldname]);
    textEditingController = TextEditingController(text: initialVal);

    // Sync external changes
    _worker = ever(formController.data, (_) {
      final newVal = _getSafeValue(formController.data[config.fieldname]);
      if (textEditingController.text != newVal) {
        textEditingController.text = newVal;
      }
    });
  }

  void onUserChanged(String val) {
    if (['Int'].contains(config.fieldtype)) {
      formController.setValue(config.fieldname, int.tryParse(val) ?? 0);
    } else if (['Float', 'Currency', 'Percent'].contains(config.fieldtype)) {
      formController.setValue(config.fieldname, double.tryParse(val) ?? 0.0);
    } else {
      formController.setValue(config.fieldname, val);
    }
  }

  Future<void> pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final val = DateFormat('yyyy-MM-dd').format(picked);
      formController.setValue(config.fieldname, val);
      textEditingController.text = val;
    }
  }

  Future<void> pickTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      // Format as HH:mm:ss
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
      final val = DateFormat('HH:mm:ss').format(dt);
      formController.setValue(config.fieldname, val);
      textEditingController.text = val;
    }
  }

  String _getSafeValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return '';
    return value.toString();
  }

  @override
  void onClose() {
    _worker?.dispose();
    textEditingController.dispose();
    super.onClose();
  }
}
