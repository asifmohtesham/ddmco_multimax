/// Frappe Link/Data value → `null` when unset (`null` or `''`).
String? pricingLink(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : s;
}

double pricingDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

bool pricingBool(dynamic v) => v == 1 || v == true || v == '1';

/// Frappe `scrub`: 'Customer Group' → 'customer_group'.
String pricingScrub(String label) => label.toLowerCase().replaceAll(' ', '_');

class PriceListInfo {
  final String name;
  final String currency;
  final bool buying;
  final bool selling;

  const PriceListInfo({
    required this.name,
    this.currency = '',
    this.buying = false,
    this.selling = false,
  });

  factory PriceListInfo.fromJson(Map<String, dynamic> j) => PriceListInfo(
        name: (j['name'] ?? '').toString(),
        currency: (j['currency'] ?? '').toString(),
        buying: pricingBool(j['buying']),
        selling: pricingBool(j['selling']),
      );

  String get kind => selling ? 'Selling' : 'Buying';
}

/// ERPNext v15 `Item Price`. Mutable working copy: the form controller edits
/// it in place through `Rx.update`.
class ItemPrice {
  String name;
  String itemCode;
  String itemName;
  String uom;
  int packingUnit;
  String priceList;
  String? customer;
  String? supplier;
  String? batchNo;
  bool buying;
  bool selling;
  String currency;
  double rate;
  String? validFrom;
  String? validUpto;
  int leadTimeDays;
  String? note;
  String? brand;
  String modified;

  ItemPrice({
    this.name = '',
    this.itemCode = '',
    this.itemName = '',
    this.uom = '',
    this.packingUnit = 0,
    this.priceList = '',
    this.customer,
    this.supplier,
    this.batchNo,
    this.buying = false,
    this.selling = false,
    this.currency = '',
    this.rate = 0,
    this.validFrom,
    this.validUpto,
    this.leadTimeDays = 0,
    this.note,
    this.brand,
    this.modified = '',
  });

  factory ItemPrice.fromJson(Map<String, dynamic> j) => ItemPrice(
        name: (j['name'] ?? '').toString(),
        itemCode: (j['item_code'] ?? '').toString(),
        itemName: (j['item_name'] ?? '').toString(),
        uom: (j['uom'] ?? '').toString(),
        packingUnit: pricingDouble(j['packing_unit']).toInt(),
        priceList: (j['price_list'] ?? '').toString(),
        customer: pricingLink(j['customer']),
        supplier: pricingLink(j['supplier']),
        batchNo: pricingLink(j['batch_no']),
        buying: pricingBool(j['buying']),
        selling: pricingBool(j['selling']),
        currency: (j['currency'] ?? '').toString(),
        rate: pricingDouble(j['price_list_rate']),
        validFrom: pricingLink(j['valid_from']),
        validUpto: pricingLink(j['valid_upto']),
        leadTimeDays: pricingDouble(j['lead_time_days']).toInt(),
        note: pricingLink(j['note']),
        brand: pricingLink(j['brand']),
        modified: (j['modified'] ?? '').toString(),
      );

  /// Save payload — ONLY the fields ERPNext lets a client set. The server
  /// overwrites buying/selling/currency/item_name/item_description/reference.
  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'uom': uom,
        'packing_unit': packingUnit,
        'price_list': priceList,
        'customer': pricingLink(customer),
        'supplier': pricingLink(supplier),
        'batch_no': pricingLink(batchNo),
        'price_list_rate': rate,
        'valid_from': pricingLink(validFrom),
        'valid_upto': pricingLink(validUpto),
        'lead_time_days': leadTimeDays,
        'note': pricingLink(note),
      };
}
