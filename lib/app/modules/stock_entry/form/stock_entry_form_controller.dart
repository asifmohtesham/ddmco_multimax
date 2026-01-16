import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:intl/intl.dart';

class StockEntryFormController extends FrappeFormController {
  StockEntryFormController() : super(doctype: 'Stock Entry');

  @override
  void onInit() {
    super.onInit();

    final args = Get.arguments;

    // Handle "New" vs "Edit" mode
    if (args == null || (args is Map && (args['mode'] == 'new' || args['name'] == null))) {
      _initNewEntry();
    } else if (args is Map && args['name'] != null) {
      load(args['name']);
    } else if (args is String) {
      load(args);
    }
  }

  void _initNewEntry() {
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Set defaults for a new document to ensure immediate UI rendering
    initialize({
      'naming_series': 'MAT-STE-.YYYY.-',
      'stock_entry_type': 'Material Transfer',
      'purpose': 'Material Transfer',
      'posting_date': now,
      'company': 'Multimax', // Default company if needed, or fetch from user defaults
      'docstatus': 0,
      'items': [],
      '__islocal': 1,
    });
  }

  // Getters for UI Helpers
  String get name => getValue('name') ?? 'New Stock Entry';
  String get status {
    final docstatus = getValue('docstatus');
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
  }

  bool get isSubmitted => getValue('docstatus') == 1;
}