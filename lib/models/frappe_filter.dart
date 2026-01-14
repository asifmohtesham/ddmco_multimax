/// Configuration for a field that can be filtered
class FrappeFilterField {
  final String fieldname;
  final String label;
  final String fieldtype; // 'Data', 'Link', 'Select', 'Date', 'Attribute'
  final String? doctype;  // For Link fields
  final List<String>? options; // For Select fields

  const FrappeFilterField({
    required this.fieldname,
    required this.label,
    this.fieldtype = 'Data',
    this.doctype,
    this.options,
  });
}

/// Represents the actual state of a single active filter row
class FrappeFilter {
  String fieldname;
  String label;
  String operator;
  String value;
  FrappeFilterField config;

  // Extra data for custom logic (e.g., attributeName)
  Map<String, dynamic> extras;

  FrappeFilter({
    required this.fieldname,
    required this.label,
    required this.config,
    this.operator = 'like',
    this.value = '',
    Map<String, dynamic>? extras,
  }) : extras = extras ?? {};

  FrappeFilter clone() {
    return FrappeFilter(
      fieldname: fieldname,
      label: label,
      operator: operator,
      value: value,
      config: config,
      extras: Map.from(extras),
    );
  }
}