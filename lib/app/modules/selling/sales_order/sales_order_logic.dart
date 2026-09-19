import 'dart:convert';

import 'package:multimax/app/data/models/sales_order_model.dart';

/// Pure Sales Order rules — no Flutter/GetX, every branch unit-tested.
/// Each rule cites the ERPNext v15 behaviour it mirrors; the verified facts
/// live in docs/superpowers/specs/2026-09-19-sales-order-doctype-design.md.

/// Statuses the dashboard chip / digest treat as "needs action".
const kSoOpenToDeliverStatuses = ['Draft', 'To Deliver and Bill', 'To Deliver'];

enum SoAction { save, submit, cancel, hold, resume, close, reopen, makeDn }

/// Resolved permissions. `null` = still loading / unknown → treated as denied.
class SoPerms {
  final bool? write;
  final bool? submit;
  final bool? cancel;
  final bool? createDn;
  const SoPerms({this.write, this.submit, this.cancel, this.createDn});
}

/// Mirrors v15 `sales_order.js` refresh(): status buttons need `submit`
/// (the whitelisted `update_status` calls has_permission(..., "submit")).
Set<SoAction> allowedActions(SalesOrder so, SoPerms p) {
  final out = <SoAction>{};
  if (so.docstatus == 0) {
    if (p.write == true) out.add(SoAction.save);
    if (p.submit == true) out.add(SoAction.submit);
    return out;
  }
  if (so.docstatus != 1) return out;

  if (p.cancel == true) out.add(SoAction.cancel);
  final notDone = so.perDelivered < 100 || so.perBilled < 100;
  if (p.submit == true) {
    switch (so.status) {
      case 'On Hold':
        out.add(SoAction.resume);
        if (notDone) out.add(SoAction.close);
      case 'Closed':
        out.add(SoAction.reopen);
      default:
        if (notDone) out.addAll({SoAction.hold, SoAction.close});
    }
  }
  if (p.createDn == true && canMakeDeliveryNote(so)) out.add(SoAction.makeDn);
  return out;
}

/// v15: status ∉ {Closed, On Hold}, not skip_delivery_note, and some row with
/// `delivered_by_supplier == 0 && qty > delivered_qty`.
bool canMakeDeliveryNote(SalesOrder so) =>
    so.docstatus == 1 &&
    so.status != 'Closed' &&
    so.status != 'On Hold' &&
    !so.skipDeliveryNote &&
    so.items.any((i) => !i.deliveredBySupplier && i.qty > i.deliveredQty);

/// The only body the app ever POSTs/PUTs. Optional user-editable fields are
/// always sent ('' when cleared) so a PUT can clear them; company / price list
/// are omitted when unknown so the server's set_missing_values fills them.
Map<String, dynamic> buildPayload(SalesOrder so) {
  final m = <String, dynamic>{
    'customer': so.customer,
    'transaction_date': so.transactionDate,
    'order_type': so.orderType,
    'delivery_date': so.deliveryDate ?? '',
    'set_warehouse': so.setWarehouse ?? '',
    'po_no': so.poNo ?? '',
    'items': so.items.map(_rowPayload).toList(),
  };
  if ((so.company ?? '').isNotEmpty) m['company'] = so.company;
  if ((so.sellingPriceList ?? '').isNotEmpty) {
    m['selling_price_list'] = so.sellingPriceList;
  }
  return m;
}

Map<String, dynamic> _rowPayload(SalesOrderItem i) => {
      if (!i.isLocal) 'name': i.name,
      'item_code': i.itemCode,
      'qty': i.qty,
      'uom': i.uom,
      'conversion_factor': i.conversionFactor,
      'rate': i.rate,
      'delivery_date': i.deliveryDate ?? '',
      'warehouse': i.warehouse ?? '',
    };

/// Dirty = the posted payloads differ (same JSON-compare approach as PO).
bool isSoDirty(SalesOrder original, SalesOrder current) =>
    jsonEncode(buildPayload(original)) != jsonEncode(buildPayload(current));

bool _before(String a, String b) {
  final da = DateTime.tryParse(a), db = DateTime.tryParse(b);
  return da != null && db != null && da.isBefore(db);
}

Map<String, String> validateRow(SalesOrderItem row, String transactionDate) {
  final e = <String, String>{};
  if (row.itemCode.isEmpty) e['item_code'] = 'Item is required';
  if (row.qty <= 0) e['qty'] = 'Quantity must be greater than 0';
  final d = row.deliveryDate ?? '';
  if (d.isNotEmpty && _before(d, transactionDate)) {
    // v15 server text, so client and server errors read the same.
    e['delivery_date'] = 'Expected Delivery Date should be after Sales Order Date';
  }
  return e;
}

/// Header-level checks mirroring v15 validate + validate_delivery_date.
Map<String, String> validateOrder(SalesOrder so) {
  final e = <String, String>{};
  if (so.customer.isEmpty) e['customer'] = 'Customer is required';
  if (so.items.isEmpty) e['items'] = 'Add at least one item';
  final needsDate = so.orderType == 'Sales' && !so.skipDeliveryNote;
  final header = so.deliveryDate ?? '';
  final anyRow = so.items.any((i) => (i.deliveryDate ?? '').isNotEmpty);
  if (needsDate && header.isEmpty && !anyRow) {
    e['delivery_date'] = 'Please enter Delivery Date';
  } else if (header.isNotEmpty && _before(header, so.transactionDate)) {
    e['delivery_date'] = 'Expected Delivery Date should be after Sales Order Date';
  }
  return e;
}

/// Typed view of `get_item_details` → message.
class ItemDetails {
  final String itemName;
  final String? uom;
  final String? stockUom;
  final double conversionFactor;
  final double priceListRate;
  final double rate;
  final String? warehouse;
  const ItemDetails({
    this.itemName = '',
    this.uom,
    this.stockUom,
    this.conversionFactor = 1,
    this.priceListRate = 0,
    this.rate = 0,
    this.warehouse,
  });
}

ItemDetails parseItemDetails(dynamic message) {
  if (message is! Map) return const ItemDetails();
  double d(String k, double fb) => (message[k] as num?)?.toDouble() ?? fb;
  String? s(String k) {
    final v = message[k];
    return (v == null || v.toString().isEmpty) ? null : v.toString();
  }

  return ItemDetails(
    itemName: s('item_name') ?? '',
    uom: s('uom'),
    stockUom: s('stock_uom'),
    conversionFactor: d('conversion_factor', 1),
    priceListRate: d('price_list_rate', 0),
    rate: d('rate', 0),
    warehouse: s('warehouse'),
  );
}

/// Chip text for a `status` filter: `'Draft'` or `['in', [...]]`.
String statusFilterLabel(dynamic value) {
  if (value is List && value.length == 2 && value[1] is List) {
    return (value[1] as List).join(', ');
  }
  return value.toString();
}

double progressFraction(double percent) => (percent / 100).clamp(0.0, 1.0);

/// Decides how the list controller's `onInit` should treat an incoming
/// `filters` map (from the dashboard's `openActionableList`, which can be
/// viewing another user's board). Returns a copy — [incoming] is never
/// mutated.
///
/// If `incoming['owner']` is set and equals [currentEmail] (non-empty), the
/// owner IS the signed-in user: fold it into the personal `mine` scope and
/// strip it from the filters (the scope toggle already implies it). Otherwise
/// — a different owner, no owner, or an unknown/empty [currentEmail] — leave
/// the filters untouched (including any `owner`), so it renders as an
/// explicit Owner chip and stays in the query under `everyone` scope.
({bool mine, Map<String, dynamic> filters}) resolveIncomingListFilters(
    Map<String, dynamic> incoming, String? currentEmail) {
  final owner = incoming['owner'];
  if (owner != null &&
      currentEmail != null &&
      currentEmail.isNotEmpty &&
      owner == currentEmail) {
    final filters = Map<String, dynamic>.from(incoming)..remove('owner');
    return (mine: true, filters: filters);
  }
  return (mine: false, filters: Map<String, dynamic>.from(incoming));
}
