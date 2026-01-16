import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/widgets/frappe_error_dialog.dart';
import 'package:intl/intl.dart';

class StockEntryFormController extends FrappeFormController {
  StockEntryFormController() : super(doctype: 'Stock Entry');

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args == null ||
        (args is Map && (args['mode'] == 'new' || args['name'] == null))) {
      _initNewEntry();
    } else if (args is Map && args['name'] != null) {
      load(args['name']);
    } else if (args is String) {
      load(args);
    }
  }

  void _initNewEntry() {
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    initialise({
      'naming_series': 'MAT-STE-.YYYY.-',
      'stock_entry_type': 'Material Transfer',
      'purpose': 'Material Transfer',
      'posting_date': now,
      // Default company if needed, or fetch from user defaults
      'company': 'Multimax',
      'docstatus': 0,
      'items': [],
      '__islocal': 1,
    });
  }

  // FIX: Override Save to Auto-Fetch Rates
  @override
  Future<void> save() async {
    bool ratesUpdated = false;

    // 1. Check for missing rates in items
    if (data['items'] != null && (data['items'] as List).isNotEmpty) {
      final items = data['items'] as List;

      for (int i = 0; i < items.length; i++) {
        var row = items[i];
        final rate =
            double.tryParse(row['basic_rate']?.toString() ?? '0') ?? 0.0;
        final itemCode = row['item_code'];

        // If rate is 0 and we have an Item Code, try to fetch it
        if (rate == 0 && itemCode != null && itemCode.toString().isNotEmpty) {
          try {
            GlobalSnackbar.loading(message: "Fetching rate for $itemCode...");

            // Call generic ERPNext API to get item details
            final details = await api.callMethod(
              'erpnext.stock.get_item_details.get_item_details',
              args: {
                'item_code': itemCode,
                // Replace with dynamic company if available
                'company': 'Multimax',
                'transaction_date':
                    data['posting_date'] ??
                    DateFormat('yyyy-MM-dd').format(DateTime.now()),
                // or Selling, depending on config
                'price_list': 'Standard Selling',
                // Add warehouse info if relevant to fetching valuation rate
                'warehouse': row['s_warehouse'] ?? row['t_warehouse'],
                'qty': row['qty'] ?? 1,
              },
            );

            if (details != null && details is Map) {
              // Update the row with fetched details
              if (details['valuation_rate'] != null) {
                row['basic_rate'] = details['valuation_rate'] == 0 ? 5 : details['valuation_rate'];
                row['amount'] =
                    (row['basic_rate'] *
                    (double.tryParse(row['qty']?.toString() ?? '1') ?? 1));
                ratesUpdated = true;
              }
            }
          } catch (e) {
            debugPrint("Failed to fetch rate for $itemCode: $e");
            // Don't block save here, let server validation fail if it must
          }
        }
      }
    }

    if (ratesUpdated) {
      data.refresh(); // Update UI with new rates
      GlobalSnackbar.success(message: "Rates updated. Saving...");
    }

    // 2. Proceed with normal save
    super.save();
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

  // Expose API for subclass use
  get api => super.api;
}
