import 'package:multimax/models/frappe_field_config.dart';

class FrappeFormSection {
  final String label;
  final bool isCollapsible; // Kept for reference, though Tabs handle visibility
  final List<FrappeFormColumn> columns;

  FrappeFormSection({
    required this.label,
    this.isCollapsible = false,
    required this.columns,
  });
}

class FrappeFormColumn {
  final String label;
  final List<FrappeFieldConfig> fields;
  final bool isExpanded; // Default expansion state

  FrappeFormColumn({
    required this.label,
    required this.fields,
    this.isExpanded = true,
  });
}
