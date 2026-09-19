import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

/// Sales Order HTTP calls. Method paths verified live on ERPNext 15.121.1.
class SalesOrderProvider {
  final ApiProvider _api = Get.find<ApiProvider>();
  static const _so = 'erpnext.selling.doctype.sales_order.sales_order';

  static const listFields = [
    'name', 'customer', 'customer_name', 'status', 'docstatus',
    'transaction_date', 'delivery_date', 'grand_total', 'currency',
    'per_delivered', 'per_billed', 'owner', 'modified',
  ];

  Future<Response> getSalesOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) =>
      _api.getDocumentList('Sales Order',
          limit: limit,
          limitStart: limitStart,
          filters: filters,
          orFilters: orFilters,
          fields: listFields,
          orderBy: orderBy);

  Future<Response> getSalesOrder(String name) =>
      _api.getDocument('Sales Order', name);

  Future<Response> create(Map<String, dynamic> data) =>
      _api.createDocument('Sales Order', data);

  Future<Response> update(String name, Map<String, dynamic> data) =>
      _api.updateDocument('Sales Order', name, data);

  Future<Response> submit(String name) =>
      _api.submitDocument('Sales Order', name);

  Future<Response> cancel(String name) => _api.callMethodPost(
      'frappe.client.cancel',
      params: {'doctype': 'Sales Order', 'name': name});

  /// status ∈ {'On Hold', 'Closed', 'Draft'} ('Draft' = Resume / Re-open).
  Future<Response> updateStatus(String name, String status) =>
      _api.callMethodPost('$_so.update_status',
          params: {'status': status, 'name': name});

  /// Desk posts the hold reason as a comment before update_status('On Hold').
  Future<Response> addHoldReason(String name, String reason, String email) =>
      _api.callMethodPost('frappe.desk.form.utils.add_comment', params: {
        'reference_doctype': 'Sales Order',
        'reference_name': name,
        'content': 'Reason for hold: $reason',
        'comment_email': email,
        'comment_by': email,
      });

  /// Server-maps the SO to a DN, inserts it as a Draft, returns its name.
  Future<String> makeDeliveryNote(String name) async {
    final mapped = await _api.callMethodPost('$_so.make_delivery_note',
        params: {'source_name': name});
    final doc = (mapped.data as Map)['message'];
    final res = await _api.callMethodPost('frappe.client.insert',
        params: {'doc': jsonEncode(doc)});
    return ((res.data as Map)['message'] as Map)['name'].toString();
  }

  Future<ItemDetails> getItemDetails(Map<String, dynamic> args) async {
    final res = await _api.callMethodPost(
        'erpnext.stock.get_item_details.get_item_details',
        params: {'args': jsonEncode(args)});
    return parseItemDetails((res.data as Map?)?['message']);
  }

  /// Customer defaults desk applies on customer change (price list, currency).
  Future<Map<String, dynamic>> getPartyDetails(
      {required String customer, required String company}) async {
    final res = await _api.callMethodPost(
        'erpnext.accounts.party.get_party_details', params: {
      'party': customer,
      'party_type': 'Customer',
      'company': company,
      'doctype': 'Sales Order',
    });
    final m = (res.data as Map?)?['message'];
    return m is Map ? Map<String, dynamic>.from(m) : {};
  }

  /// Stock Settings' `enable_stock_reservation`, via the whitelisted
  /// `get_stock_reservation_status` (Selling Settings/Stock Settings
  /// themselves are readable only by System/Sales Manager, this method is
  /// not). Fail-closed: `false` on any error, so the Reserve Stock control
  /// stays hidden exactly as desk hides it when the setting is off.
  Future<bool> stockReservationEnabled() async {
    try {
      final res = await _api.callMethod('$_so.get_stock_reservation_status');
      final m = (res.data as Map?)?['message'];
      return m == 1 || m == true || m == '1';
    } catch (_) {
      return false;
    }
  }

  /// Per-document permission (submit / cancel). Fail-closed on any error.
  Future<bool> hasDocPerm(String name, String ptype) async {
    try {
      final res = await _api.hasDocPermission('Sales Order', name, ptype);
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }
}
