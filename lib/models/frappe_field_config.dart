class FrappeFieldConfig {
  final String label;
  final String fieldname;
  final String fieldtype;
  final bool reqd;
  final bool readOnly;
  final bool hidden;
  final List<String>? options;
  final String? optionsLink;
  final String? dependsOn; // New: Stores "eval:doc.field == 'value'" logic
  final List<FrappeFieldConfig>? childFields; // For Tables
  final bool inListView;

  FrappeFieldConfig({
    required this.label,
    required this.fieldname,
    required this.fieldtype,
    this.reqd = false,
    this.readOnly = false,
    this.hidden = false,
    this.options,
    this.optionsLink,
    this.dependsOn,
    this.childFields,
    this.inListView = false,
  });
}
