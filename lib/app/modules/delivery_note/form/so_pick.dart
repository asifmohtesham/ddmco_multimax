import 'package:multimax/app/data/models/delivery_note_model.dart';

/// One Sales Order Item, seen as a pick target for a Delivery Note.
///
/// A DN row is bound to its SO line by `so_detail` (the Sales Order Item's
/// `name`) plus `against_sales_order`; ERPNext only advances the order's
/// `per_delivered` through that link.
class SoPickLine {
  final String soDetail;
  final int idx;
  final String itemCode;
  final String itemName;
  final double orderedQty;
  final double deliveredQty;
  final double rate;
  final String? uom;
  final double conversionFactor;
  final String? warehouse;

  const SoPickLine({
    required this.soDetail,
    required this.idx,
    required this.itemCode,
    required this.itemName,
    required this.orderedQty,
    required this.deliveredQty,
    required this.rate,
    this.uom,
    this.conversionFactor = 1,
    this.warehouse,
  });

  /// Qty still owed on the order (delivered_qty counts submitted DNs only).
  double get pendingQty =>
      (orderedQty - deliveredQty).clamp(0.0, double.infinity);

  factory SoPickLine.fromSalesOrderItem(Map<String, dynamic> j) => SoPickLine(
        soDetail: (j['name'] ?? '').toString(),
        idx: _int(j['idx']),
        itemCode: (j['item_code'] ?? '').toString(),
        itemName: (j['item_name'] ?? j['item_code'] ?? '').toString(),
        orderedQty: _num(j['qty']),
        deliveredQty: _num(j['delivered_qty']),
        rate: _num(j['rate']),
        uom: j['uom'] as String?,
        conversionFactor: j['conversion_factor'] == null
            ? 1
            : _num(j['conversion_factor']),
        warehouse: j['warehouse'] as String?,
      );

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}

/// The Sales Order a Delivery Note is being picked against.
class SoPickContext {
  final String name;
  final String customer;
  final String? customerName;
  final String? deliveryDate;
  final List<SoPickLine> lines;

  const SoPickContext({
    required this.name,
    required this.customer,
    this.customerName,
    this.deliveryDate,
    required this.lines,
  });

  factory SoPickContext.fromSalesOrder(Map<String, dynamic> so) =>
      SoPickContext(
        name: (so['name'] ?? '').toString(),
        customer: (so['customer'] ?? '').toString(),
        customerName: so['customer_name'] as String?,
        deliveryDate: so['delivery_date'] as String?,
        lines: ((so['items'] as List?) ?? const [])
            .map((e) => SoPickLine.fromSalesOrderItem(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  SoPickLine? lineByDetail(String? soDetail) {
    if (soDetail == null) return null;
    for (final l in lines) {
      if (l.soDetail == soDetail) return l;
    }
    return null;
  }

  /// The warehouse every line ships from, or null when lines disagree.
  String? get commonWarehouse {
    final whs = lines
        .map((l) => l.warehouse)
        .whereType<String>()
        .where((w) => w.isNotEmpty)
        .toSet();
    return whs.length == 1 ? whs.first : null;
  }
}

enum SoPickOutcome { ok, notOnOrder, fullyPicked }

class SoPickResolution {
  final SoPickOutcome outcome;
  final SoPickLine? line;
  final double remaining;
  const SoPickResolution(this.outcome, {this.line, this.remaining = 0});
}

class SoPickProgress {
  final int totalLines;
  final int completeLines;
  final double pickedQty;
  final double pendingQty;
  const SoPickProgress({
    required this.totalLines,
    required this.completeLines,
    required this.pickedQty,
    required this.pendingQty,
  });
  bool get isComplete => totalLines > 0 && completeLines == totalLines;
  double get fraction =>
      pendingQty <= 0 ? 0 : (pickedQty / pendingQty).clamp(0.0, 1.0);
}

/// Pure Sales-Order picking rules — kept free of GetX so they unit-test.
class SoPick {
  SoPick._();

  /// Header fields copied from `make_delivery_note`'s mapped DN onto a new,
  /// item-less draft so it validates against the SO exactly as desk would.
  static const headerKeys = [
    'company', 'currency', 'conversion_rate', 'selling_price_list',
    'price_list_currency', 'plc_conversion_rate', 'ignore_pricing_rule',
    'customer_address', 'address_display', 'shipping_address_name',
    'shipping_address', 'dispatch_address_name', 'company_address',
    'contact_person', 'contact_display', 'contact_mobile', 'contact_email',
    'territory', 'customer_group', 'tax_category', 'taxes_and_charges',
    'taxes', 'set_warehouse', 'project', 'cost_center', 'po_no', 'po_date',
    'sales_partner', 'commission_rate', 'tc_name', 'terms',
    'apply_discount_on', 'additional_discount_percentage', 'sales_team',
  ];

  static const _rowMetaKeys = {
    'name', 'parent', 'parenttype', 'parentfield', 'owner', 'creation',
    'modified', 'modified_by', 'docstatus', 'idx', '__islocal', '__unsaved',
  };

  static Map<String, dynamic> headerFromMappedDn(Map<String, dynamic> dn) {
    final out = <String, dynamic>{};
    for (final k in headerKeys) {
      final v = dn[k];
      if (v == null) continue;
      if (v is List) {
        out[k] = v
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.fromEntries(row.entries
                .where((e) => !_rowMetaKeys.contains(e.key))
                .map((e) => MapEntry(e.key.toString(), e.value))))
            .toList();
      } else {
        out[k] = v;
      }
    }
    return out;
  }

  static double pickedQty(String soDetail, List<DeliveryNoteItem> rows,
          {String? excludeRowName}) =>
      rows
          .where((r) =>
              r.soDetail == soDetail &&
              (excludeRowName == null || r.name != excludeRowName))
          .fold(0.0, (s, r) => s + r.qty);

  static double remainingFor(SoPickLine line, List<DeliveryNoteItem> rows,
          {String? excludeRowName}) =>
      (line.pendingQty -
              pickedQty(line.soDetail, rows, excludeRowName: excludeRowName))
          .clamp(0.0, double.infinity);

  /// Which SO line a scanned [itemCode] should be picked into: the first line
  /// (by SO order) for that item that still has room.
  static SoPickResolution resolveLine(
      List<SoPickLine> lines, String itemCode, List<DeliveryNoteItem> rows) {
    final code = itemCode.trim().toLowerCase();
    final matches =
        lines.where((l) => l.itemCode.trim().toLowerCase() == code).toList();
    if (matches.isEmpty) {
      return const SoPickResolution(SoPickOutcome.notOnOrder);
    }
    for (final l in matches) {
      final rem = remainingFor(l, rows);
      if (rem > 0) {
        return SoPickResolution(SoPickOutcome.ok, line: l, remaining: rem);
      }
    }
    return SoPickResolution(SoPickOutcome.fullyPicked, line: matches.first);
  }

  /// Lines already delivered in full on the server are not part of this pick.
  static SoPickProgress progress(
      List<SoPickLine> lines, List<DeliveryNoteItem> rows) {
    final open = lines.where((l) => l.pendingQty > 0).toList();
    var complete = 0;
    var picked = 0.0;
    var pending = 0.0;
    for (final l in open) {
      final p = pickedQty(l.soDetail, rows);
      picked += p.clamp(0.0, l.pendingQty);
      pending += l.pendingQty;
      if (p >= l.pendingQty) complete++;
    }
    return SoPickProgress(
      totalLines: open.length,
      completeLines: complete,
      pickedQty: picked,
      pendingQty: pending,
    );
  }
}

extension SoPickRow on DeliveryNoteItem {
  /// Binds a freshly built row to its SO line: link fields, plus the SO's
  /// rate/UOM so the DN bills what was ordered. No-op without a line.
  ///
  /// `custom_invoice_serial_number` is a mandatory Int on DN (and Packing
  /// Slip) items. For POS Uploads it is the source line's 1-based idx; the
  /// SO line idx is the same notion, and keeps Packing Slip's per-serial
  /// grouping working for SO deliveries.
  DeliveryNoteItem withSoLine(SoPickLine? line, String? salesOrder) {
    if (line == null || salesOrder == null) return this;
    return copyWith(
      againstSalesOrder: salesOrder,
      soDetail: line.soDetail,
      rate: line.rate,
      uom: line.uom ?? uom,
      conversionFactor: line.conversionFactor,
      customInvoiceSerialNumber: line.idx.toString(),
    );
  }
}
