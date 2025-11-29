import 'package:flutter/foundation.dart'; // For @required if using older Flutter, or just non-nullable types

enum FrappeFieldtype {
  // Common fieldtypes - expand as needed
  Data,
  Select,
  Link,
  Table, // Child Table
  Int,
  Float,
  Currency,
  Check,
  Date,
  Datetime,
  Time,
  SmallText, // Textarea
  LongText,
  HTML,
  Button,
  Image,
  Attach,
  Barcode,
  Password,
  Color,
  // Add more as you identify them from your doctypes
  Unsupported, TextEditor, Percent, SectionBreak, ColumnBreak, TabBreak, ReadOnly, // For types you don't yet handle
}

class FrappeField {
  final String fieldname;
  final String label;
  final FrappeFieldtype fieldtype;
  final String? options; // For Select, Link (target doctype), Table (target child doctype)
  final bool isRequired; // 'reqd' field (0 or 1)
  final bool isReadOnly; // 'read_only' field (0 or 1)
  final String? defaultValue; // 'default'
  final String? description;
  final bool isHidden; // 'hidden' field (0 or 1)
  final int? length; // For Data fields

  // You might add more properties like 'allow_on_submit', 'depends_on', 'mandatory_depends_on'
  // 'fetch_from', 'fetch_if_empty' for more advanced dynamic behaviors.

  FrappeField({
    required this.fieldname,
    required this.label,
    required this.fieldtype,
    this.options,
    required this.isRequired,
    required this.isReadOnly,
    this.defaultValue,
    this.description,
    required this.isHidden,
    this.length,
  });

  factory FrappeField.fromJson(Map<String, dynamic> json) {
    return FrappeField(
      fieldname: json['fieldname'] as String,
      label: json['label'] as String? ?? json['fieldname'] as String, // Fallback label to fieldname
      fieldtype: _parseFieldtype(json['fieldtype'] as String?),
      options: json['options'] as String?,
      isRequired: (json['reqd'] == 1),
      isReadOnly: (json['read_only'] == 1),
      defaultValue: json['default'] as String?,
      description: json['description'] as String?,
      isHidden: (json['hidden'] == 1),
      length: json['length'] as int?,
    );
  }

  static FrappeFieldtype _parseFieldtype(String? typeStr) {
    if (typeStr == null) return FrappeFieldtype.Unsupported;
    switch (typeStr) {
      case 'Data': return FrappeFieldtype.Data;
      case 'Select': return FrappeFieldtype.Select;
      case 'Link': return FrappeFieldtype.Link;
      case 'Table': return FrappeFieldtype.Table;
      case 'Int': return FrappeFieldtype.Int;
      case 'Float': return FrappeFieldtype.Float;
      case 'Currency': return FrappeFieldtype.Currency;
      case 'Check': return FrappeFieldtype.Check;
      case 'Date': return FrappeFieldtype.Date;
      case 'Datetime': return FrappeFieldtype.Datetime;
      case 'Time': return FrappeFieldtype.Time;
      case 'Small Text': return FrappeFieldtype.SmallText;
      case 'Long Text': return FrappeFieldtype.LongText;
      // Add all other cases
      default:
        // Use standard print for logging within the model
        print("WARNING: Unsupported Frappe Fieldtype encountered in model: $typeStr");
        return FrappeFieldtype.Unsupported;
    }
  }
}
