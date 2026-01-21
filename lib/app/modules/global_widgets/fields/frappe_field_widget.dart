import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/fields/searchable_link_field.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_date_picker.dart';
import 'package:multimax/app/modules/global_widgets/fields/frappe_table_field.dart';

class FrappeFieldWidget extends StatelessWidget {
  final Map<String, dynamic> fieldMeta;
  final dynamic value;
  final Function(dynamic) onChanged;
  final Map<String, dynamic> doc;
  final Map<String, dynamic>? filters;

  const FrappeFieldWidget({
    super.key,
    required this.fieldMeta,
    required this.value,
    required this.onChanged,
    required this.doc,
    this.filters
  });

  @override
  Widget build(BuildContext context) {
    // Standardise field type from metadata
    final String type = fieldMeta['fieldtype'] ?? 'Data';
    final String label = fieldMeta['label'] ?? '';
    final String fieldname = fieldMeta['fieldname'] ?? '';

    // Determine Read-Only Status (Backend Meta + Client Logic)
    final bool isReadOnly =
        fieldMeta['read_only'] == 1 || fieldMeta['read_only'] == true;

    // 1. GLOBAL VISIBILITY LOGIC
    // Handle 'depends_on' or 'hidden' flags if necessary.
    // Basic implementation:
    if (fieldMeta['hidden'] == 1) return const SizedBox.shrink();

    // 2. WIDGET FACTORY
    switch (type) {
      // --- TEXT & STRING INPUTS ---
      case 'Data':
      case 'Autocomplete': // TODO: Treat as Data for now, can be enhanced with Autocomplete widget
      case 'Title':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          keyboardType: TextInputType.text,
        );

      case 'Password':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          obscureText: true,
          maxLines: 1,
        );

      // --- NUMERIC INPUTS ---
      case 'Int':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
          readOnly: isReadOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
        );

      case 'Float':
      case 'Currency':
      case 'Percent':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: (v) => onChanged(double.tryParse(v) ?? 0.0),
          readOnly: isReadOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          prefixIcon: type == 'Currency'
              ? const Icon(Icons.attach_money, size: 16)
              : null,
        );

      // --- LONG TEXT / CODE ---
      case 'Text':
      case 'Small Text':
      case 'Long Text':
      case 'Text Editor':
      case 'Code':
      case 'JSON':
      case 'Markdown Editor':
      case 'HTML': // Editable HTML source or plain text fallback
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          keyboardType: TextInputType.multiline,
          maxLines: type == 'Small Text' ? 2 : 4,
          alignLabelWithHint: true,
        );

      // --- SELECTION & LINKS ---
      case 'Link':
        return SearchableLinkField(
          label: label,
          doctype: fieldMeta['options'] ?? '',
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          filters: filters, // Add custom filter logic here if needed
        );

      case 'Dynamic Link':
        // Dynamic Links depend on another field (e.g., 'reference_doctype') to know which DocType to search.
        // Simplified fallback to generic text or disabled if complex.
        return _buildTextField(
          label: "$label (Dynamic)",
          value: value,
          onChanged: onChanged,
          readOnly: true,
          // Difficult to implement without complex controller logic
          helperText: "Dynamic Link linking is currently read-only",
        );

      case 'Select':
        return _buildDropdown(
          label: label,
          value: value,
          options: fieldMeta['options'],
          onChanged: onChanged,
          readOnly: isReadOnly,
        );

      // --- BOOLEAN ---
      case 'Check':
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          value: value == 1 || value == true,
          onChanged: isReadOnly ? null : (v) => onChanged(v == true ? 1 : 0),
          controlAffinity: ListTileControlAffinity.leading,
        );

      // --- DATE & TIME ---
      case 'Date':
      case 'Datetime':
        return FrappeDatePicker(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          type: type, // Pass type to handle Date vs Datetime logic in picker
        );

      case 'Time':
      case 'Duration':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: true,
          // TODO: Implement FrappeTimePicker
          suffixIcon: const Icon(Icons.access_time),
          onTap: () async {
            if (isReadOnly) return;
            // Placeholder for Time Picker Logic
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (time != null) {
              onChanged("${time.hour}:${time.minute}:00"); // Standard HH:mm:ss
            }
          },
        );

      // --- MEDIA & FILES ---
      case 'Attach':
      case 'Attach Image':
        return _buildAttachmentField(label, value, isReadOnly);

      case 'Signature':
        return _buildSignatureField(label, value, isReadOnly);

      case 'Image':
        // Read-only image display (usually fetched from another field)
        return value != null
            ? Image.network(value, height: 100, fit: BoxFit.cover)
            : const SizedBox.shrink();

      // --- SPECIAL INPUTS ---
      case 'Barcode':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: isReadOnly
                ? null
                : () {
                    // Trigger Barcode Scanner
                    // Get.to(() => ScanScreen())?.then((val) => onChanged(val));
                  },
          ),
        );

      case 'Geolocation':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          suffixIcon: const Icon(Icons.location_on),
        );

      case 'Color':
        return _buildTextField(
          label: label,
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          prefixIcon: Icon(Icons.circle, color: _parseColor(value)),
        );

      case 'Rating':
        // Simplified Rating (Integer Input 1-5)
        return _buildTextField(
          label: "$label (1-5)",
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
          keyboardType: TextInputType.number,
        );

      // --- CHILD TABLES ---
      case 'Table':
        return FrappeTableField(
          label: label,
          items: value is List ? List.from(value) : [],
          fieldMeta: fieldMeta,
          onRowUpdate: (index, rowData) {
            List<dynamic> list = List.from(value is List ? value : []);
            if (index < list.length) {
              list[index] = rowData;
              onChanged(list);
            }
          },
        );

      // --- LAYOUT & ACTIONS ---
      case 'Button':
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isReadOnly
                ? null
                : () {
                    // Handle Button Click Action (Usually defined in Client Scripts)
                  },
            child: Text(label),
          ),
        );

      case 'Heading':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        );

      case 'Section Break':
      case 'Column Break':
      case 'Tab Break':
      case 'Fold':
        // Layout fields should be handled by the parent container/builder.
        // If they reach here, render nothing to avoid visual clutter.
        return const SizedBox.shrink();

      // --- DEFAULT FALLBACK ---
      default:
        return _buildTextField(
          label: "$label ($type)",
          value: value,
          onChanged: onChanged,
          readOnly: isReadOnly,
        );
    }
  }

  // --- HELPER WIDGETS ---

  Widget _buildTextField({
    required String label,
    required dynamic value,
    required Function(dynamic) onChanged,
    required bool readOnly,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int maxLines = 1,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    bool alignLabelWithHint = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        initialValue: value?.toString(),
        readOnly: readOnly,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          border: const OutlineInputBorder(),
          alignLabelWithHint: alignLabelWithHint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required dynamic value,
    required dynamic options,
    required Function(dynamic) onChanged,
    required bool readOnly,
  }) {
    // Parse Options: Can be String (newline separated) or List
    List<String> items = [];
    if (options is String) {
      items = options.split('\n').where((s) => s.isNotEmpty).toList();
    } else if (options is List) {
      items = options.map((e) => e.toString()).toList();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: (value != null && items.contains(value)) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        items: items
            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
            .toList(),
        onChanged: readOnly ? null : onChanged,
      ),
    );
  }

  Widget _buildAttachmentField(String label, dynamic value, bool readOnly) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: readOnly
            ? null
            : () {
                // TODO: Implement File Picker
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.attach_file),
          ),
          child: Text(
            value != null ? "File Attached" : "Tap to attach",
            style: TextStyle(color: value != null ? Colors.blue : Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildSignatureField(String label, dynamic value, bool readOnly) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            value != null ? "Signed" : "Signature ($label)",
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Color? _parseColor(dynamic value) {
    if (value is String && value.startsWith('#')) {
      return Color(int.parse(value.substring(1, 7), radix: 16) + 0xFF000000);
    }
    return Colors.grey;
  }
}
