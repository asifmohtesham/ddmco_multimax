import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// The one way the app turns a Sales Order into a Delivery Note.
///
/// Pick List policy: a Delivery Note is never pre-filled from its Sales
/// Order. Floor staff physically scan each batched item, so stock is right
/// in real time. Every entry point (Dashboard sheet, Sales Order form)
/// therefore opens the scan-to-pick Delivery Note: the order's existing
/// draft when there is one (so two people never start parallel DNs for the
/// same order), else a new, empty DN bound to the order.
class SoDeliveryLauncher {
  SoDeliveryLauncher._();

  /// Route arguments for the Delivery Note form.
  static Map<String, dynamic> routeArgs(String salesOrder, String? draftDn) =>
      (draftDn != null && draftDn.isNotEmpty)
          ? {'name': draftDn, 'mode': 'edit'}
          : {'name': '', 'mode': 'new', 'salesOrderName': salesOrder};

  /// Name of a draft Delivery Note with a row against [salesOrder], if any.
  static Future<String?> findDraftDn(String salesOrder,
      {ApiProvider? api}) async {
    final res = await (api ?? Get.find<ApiProvider>()).getDocumentList(
      'Delivery Note',
      limit: 1,
      fields: const ['name'],
      filterTuples: [
        ['Delivery Note', 'docstatus', '=', 0],
        ['Delivery Note Item', 'against_sales_order', '=', salesOrder],
      ],
    );
    final data = res.data is Map ? res.data['data'] : null;
    if (data is List && data.isNotEmpty) {
      return (data.first as Map)['name']?.toString();
    }
    return null;
  }

  /// Opens the scan-to-pick Delivery Note for [salesOrder]. [beforeNavigate]
  /// runs once the draft lookup is done (e.g. to close a picker sheet).
  /// Returns the resumed draft's name, or null when a new DN was started.
  static Future<String?> open(String salesOrder,
      {void Function()? beforeNavigate}) async {
    final draft = await findDraftDn(salesOrder);
    beforeNavigate?.call();
    Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
        arguments: routeArgs(salesOrder, draft));
    return draft;
  }
}
