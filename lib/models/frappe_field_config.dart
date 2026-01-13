/// Defines the metadata for a single field in a Frappe DocType.
class FrappeFieldConfig {
  final String label;
  final String fieldname;
  final String fieldtype;
  final bool reqd;
  final bool readOnly;
  final bool hidden;
  final bool inListView; // Critical for Mobile Cards summaries
  final List<String>? options; // For Select fields
  final String? optionsLink; // For Link fields (the DocType target)
  final List<FrappeFieldConfig>? childFields; // For Table fields definitions

  FrappeFieldConfig({
    required this.label,
    required this.fieldname,
    required this.fieldtype,
    this.reqd = false,
    this.readOnly = false,
    this.hidden = false,
    this.inListView = false,
    this.options,
    this.optionsLink,
    this.childFields,
  });
}