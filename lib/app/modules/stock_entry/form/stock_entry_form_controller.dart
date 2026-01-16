import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
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
      'company': 'Multimax', // Default company if needed, or fetch from user defaults
      'docstatus': 0,
      'items': [],
      '__islocal': 1,
    });
  }

  @override
  Future<void> save() async {
    bool ratesUpdated = false;

    // Attempt to auto-fetch rates for items with 0 rate
    if (data['items'] != null && (data['items'] as List).isNotEmpty) {
      final items = data['items'] as List;

      for (int i = 0; i < items.length; i++) {
        var row = items[i];
        final rate =
            double.tryParse(row['basic_rate']?.toString() ?? '0') ?? 0.0;
        final itemCode = row['item_code'];

        // Only try fetching if rate is missing
        if (rate <= 0 && itemCode != null && itemCode.toString().isNotEmpty) {
          try {
            GlobalSnackbar.loading(message: "Fetching rate for $itemCode...");

            final details = await api.callMethod(
              'erpnext.stock.get_item_details.get_item_details',
              args: {
                'item_code': itemCode,
                'company': 'Multimax',
                'transaction_date':
                    data['posting_date'] ??
                    DateFormat('yyyy-MM-dd').format(DateTime.now()),
                'price_list': 'Standard Buying',
                'warehouse': row['s_warehouse'] ?? row['t_warehouse'],
                'qty': row['qty'] ?? 1,
              },
            );

            if (details != null && details is Map) {
              final newRate =
                  details['valuation_rate'] ??
                  details['price_list_rate'] ??
                  0.0;
              if (newRate > 0) {
                row['basic_rate'] = newRate;
                row['amount'] =
                    (newRate *
                    (double.tryParse(row['qty']?.toString() ?? '1') ?? 1));
                ratesUpdated = true;
              }
            }
          } catch (e) {
            debugPrint("Failed to fetch rate: $e");
            // Ignore error, proceed to save and let server validate
          }
        }
      }
    }

    if (ratesUpdated) {
      data.refresh();
      if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();
    }

    // Proceed with API Save regardless of fetch success/failure.
    // The server will return a 417 if data is invalid, which API Service now displays correctly.
    super.save();
  }

  String get name => getValue('name') ?? 'New Stock Entry';

  String get status {
    final docstatus = getValue('docstatus');
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
  }

  bool get isSubmitted => getValue('docstatus') == 1;

  @override
  get api => super.api;
}
