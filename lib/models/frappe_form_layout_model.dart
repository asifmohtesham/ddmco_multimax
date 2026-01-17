import 'package:get/get.dart';
import 'package:multimax/models/frappe_field_config.dart';

class FrappeFormTab {
  final String label;
  final List<FrappeFormSection> sections;

  FrappeFormTab({required this.label, required this.sections});
}

class FrappeFormSection {
  final String label;
  final bool isCollapsible;
  final RxBool isExpanded;
  final String? dependsOn; // New: Section Visibility
  final List<FrappeFieldConfig> fields;

  FrappeFormSection({
    required this.label,
    this.isCollapsible = false,
    required this.fields,
    this.dependsOn,
    bool isExpanded = true,
  }) : isExpanded = isExpanded.obs;
}
