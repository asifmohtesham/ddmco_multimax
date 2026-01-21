import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FrappeDatePicker extends StatelessWidget {
  final String label;
  final String? value;
  final Function(dynamic) onChanged;
  final String type;
  final bool readOnly;

  const FrappeDatePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.type = 'Date',
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: readOnly ? null : () async {
        DateTime initialDate = DateTime.now();
        if (value != null && value!.isNotEmpty) {
          try {
            initialDate = DateTime.parse(value!);
          } catch (_) {}
        }

        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );

        if (picked != null) {
          onChanged(DateFormat('yyyy-MM-dd').format(picked));
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
          enabled: !readOnly,
        ),
        child: Text(
          value ?? '',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}