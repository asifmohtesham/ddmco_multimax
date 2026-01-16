import 'package:multimax/models/frappe_field_config.dart';

class FrappeFormSection {
  final String label;
  final bool isCollapsible;
  final bool isCollapsed; // Initial state
  final List<FrappeFieldConfig> fields;

  FrappeFormSection({
    required this.label,
    this.isCollapsible = false,
    this.isCollapsed = false,
    required this.fields,
  });
}