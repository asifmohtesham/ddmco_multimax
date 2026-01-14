import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_list_controller.dart';
import 'package:multimax/models/frappe_filter.dart';

class StockEntryController extends FrappeListController {
  @override
  String get doctype => 'Stock Entry';

  @override
  List<String> get defaultFields => [
    'name',
    'stock_entry_type',
    'purpose',
    'from_warehouse',
    'to_warehouse',
    'posting_date',
    'docstatus',
    'total_outgoing_value'
  ];

  @override
  List<FrappeFilterField> get filterableFields => [
    const FrappeFilterField(fieldname: 'name', label: 'ID'),
    const FrappeFilterField(
        fieldname: 'stock_entry_type',
        label: 'Type',
        fieldtype: 'Link',
        doctype: 'Stock Entry Type'
    ),
    const FrappeFilterField(
        fieldname: 'purpose',
        label: 'Purpose',
        fieldtype: 'Select',
        options: [
          'Material Issue',
          'Material Receipt',
          'Material Transfer',
          'Material Consumption for Manufacture',
          'Manufacture',
          'Repack',
          'Send to Subcontractor'
        ]
    ),
    const FrappeFilterField(
        fieldname: 'from_warehouse',
        label: 'Source Warehouse',
        fieldtype: 'Link',
        doctype: 'Warehouse'
    ),
    const FrappeFilterField(
        fieldname: 'to_warehouse',
        label: 'Target Warehouse',
        fieldtype: 'Link',
        doctype: 'Warehouse'
    ),
    const FrappeFilterField(fieldname: 'posting_date', label: 'Date', fieldtype: 'Date'),
  ];

  // Helper to resolve status string from docstatus
  String getStatus(Map<String, dynamic> doc) {
    final int docstatus = doc['docstatus'] ?? 0;
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
  }
}