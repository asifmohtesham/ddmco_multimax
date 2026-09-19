/// Sales Order + rows. Parsing only: the payload the app posts is built by
/// `buildPayload` in sales_order_logic.dart so read-only / server-computed
/// fields (totals, VAT custom columns, status) can never leak into a save.
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
String? _s(dynamic v) =>
    (v == null || v.toString().isEmpty) ? null : v.toString();
bool _b(dynamic v) => v == true || v == 1;

class SalesOrder {
  final String name;
  final String customer;
  final String customerName;
  final String transactionDate;
  final String? deliveryDate;
  final String orderType;
  final String? company;
  final String currency;
  final String? sellingPriceList;
  final String? setWarehouse;
  final String? poNo;
  final bool skipDeliveryNote;
  /// v15 header flag: the server creates Stock Reservation Entries on submit
  /// when this is set (SalesOrder.on_submit). Field default is 0.
  final bool reserveStock;
  final String status;
  final int docstatus;
  final double perDelivered;
  final double perBilled;
  final double totalQty;
  final double totalTaxesAndCharges;
  final double grandTotal;
  final double roundedTotal;
  final String owner;
  final String modified;
  final List<SalesOrderItem> items;

  const SalesOrder({
    required this.name,
    this.customer = '',
    this.customerName = '',
    this.transactionDate = '',
    this.deliveryDate,
    this.orderType = 'Sales',
    this.company,
    this.currency = 'AED',
    this.sellingPriceList,
    this.setWarehouse,
    this.poNo,
    this.skipDeliveryNote = false,
    this.reserveStock = false,
    this.status = 'Draft',
    this.docstatus = 0,
    this.perDelivered = 0,
    this.perBilled = 0,
    this.totalQty = 0,
    this.totalTaxesAndCharges = 0,
    this.grandTotal = 0,
    this.roundedTotal = 0,
    this.owner = '',
    this.modified = '',
    this.items = const [],
  });

  static SalesOrder blank(
          {required String transactionDate, required String company}) =>
      SalesOrder(
        name: 'New Sales Order',
        transactionDate: transactionDate,
        company: company,
        status: 'Not Saved',
      );

  factory SalesOrder.fromJson(Map<String, dynamic> j) => SalesOrder(
        name: (j['name'] ?? '').toString(),
        customer: (j['customer'] ?? '').toString(),
        customerName: (j['customer_name'] ?? '').toString(),
        transactionDate: (j['transaction_date'] ?? '').toString(),
        deliveryDate: _s(j['delivery_date']),
        orderType: _s(j['order_type']) ?? 'Sales',
        company: _s(j['company']),
        currency: _s(j['currency']) ?? 'AED',
        sellingPriceList: _s(j['selling_price_list']),
        setWarehouse: _s(j['set_warehouse']),
        poNo: _s(j['po_no']),
        skipDeliveryNote: _b(j['skip_delivery_note']),
        reserveStock: _b(j['reserve_stock']),
        status: _s(j['status']) ?? 'Draft',
        docstatus: (j['docstatus'] as num?)?.toInt() ?? 0,
        perDelivered: _d(j['per_delivered']),
        perBilled: _d(j['per_billed']),
        totalQty: _d(j['total_qty']),
        totalTaxesAndCharges: _d(j['total_taxes_and_charges']),
        grandTotal: _d(j['grand_total']),
        roundedTotal: _d(j['rounded_total']),
        owner: (j['owner'] ?? '').toString(),
        modified: (j['modified'] ?? '').toString(),
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => SalesOrderItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  SalesOrder copyWith({
    String? customer,
    String? customerName,
    String? transactionDate,
    String? deliveryDate,
    String? orderType,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? setWarehouse,
    String? poNo,
    String? status,
    bool? reserveStock,
    List<SalesOrderItem>? items,
  }) =>
      SalesOrder(
        name: name,
        customer: customer ?? this.customer,
        customerName: customerName ?? this.customerName,
        transactionDate: transactionDate ?? this.transactionDate,
        deliveryDate: deliveryDate ?? this.deliveryDate,
        orderType: orderType ?? this.orderType,
        company: company ?? this.company,
        currency: currency ?? this.currency,
        sellingPriceList: sellingPriceList ?? this.sellingPriceList,
        setWarehouse: setWarehouse ?? this.setWarehouse,
        poNo: poNo ?? this.poNo,
        skipDeliveryNote: skipDeliveryNote,
        reserveStock: reserveStock ?? this.reserveStock,
        status: status ?? this.status,
        docstatus: docstatus,
        perDelivered: perDelivered,
        perBilled: perBilled,
        totalQty: totalQty,
        totalTaxesAndCharges: totalTaxesAndCharges,
        grandTotal: grandTotal,
        roundedTotal: roundedTotal,
        owner: owner,
        modified: modified,
        items: items ?? this.items,
      );
}

class SalesOrderItem {
  final String? name;
  final String itemCode;
  final String itemName;
  final double qty;
  final String? uom;
  final String? stockUom;
  final double conversionFactor;
  final double rate;
  final double priceListRate;
  final double amount;
  final String? deliveryDate;
  final String? warehouse;
  final double deliveredQty;
  final bool deliveredBySupplier;
  final double taxAmount;   // custom UAE VAT column (read-only)
  final double totalAmount; // custom UAE VAT column (read-only)

  const SalesOrderItem({
    this.name,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    this.uom,
    this.stockUom,
    this.conversionFactor = 1,
    this.rate = 0,
    this.priceListRate = 0,
    this.amount = 0,
    this.deliveryDate,
    this.warehouse,
    this.deliveredQty = 0,
    this.deliveredBySupplier = false,
    this.taxAmount = 0,
    this.totalAmount = 0,
  });

  /// Rows added in the app carry a `local_<ms>` id until the first save.
  bool get isLocal => name?.startsWith('local_') ?? true;

  /// Returns a copy with [name] set. `name` has no setter and isn't a
  /// `copyWith` param (it identifies the row); this exists only so
  /// `SalesOrderFormController.addItem` can assign a temporary unique id to
  /// a locally-added row before it has a server name — two rows with a null
  /// `name` would otherwise be indistinguishable to `updateItem`/`deleteItem`
  /// (which match by `name`) and to the Items tab's `Dismissible`/highlight
  /// keys.
  SalesOrderItem withName(String name) => SalesOrderItem(
        name: name,
        itemCode: itemCode,
        itemName: itemName,
        qty: qty,
        uom: uom,
        stockUom: stockUom,
        conversionFactor: conversionFactor,
        rate: rate,
        priceListRate: priceListRate,
        amount: amount,
        deliveryDate: deliveryDate,
        warehouse: warehouse,
        deliveredQty: deliveredQty,
        deliveredBySupplier: deliveredBySupplier,
        taxAmount: taxAmount,
        totalAmount: totalAmount,
      );

  factory SalesOrderItem.fromJson(Map<String, dynamic> j) => SalesOrderItem(
        name: _s(j['name']),
        itemCode: (j['item_code'] ?? '').toString(),
        itemName: (j['item_name'] ?? '').toString(),
        qty: _d(j['qty']),
        uom: _s(j['uom']),
        stockUom: _s(j['stock_uom']),
        conversionFactor:
            j['conversion_factor'] == null ? 1 : _d(j['conversion_factor']),
        rate: _d(j['rate']),
        priceListRate: _d(j['price_list_rate']),
        amount: _d(j['amount']),
        deliveryDate: _s(j['delivery_date']),
        warehouse: _s(j['warehouse']),
        deliveredQty: _d(j['delivered_qty']),
        deliveredBySupplier: _b(j['delivered_by_supplier']),
        taxAmount: _d(j['tax_amount']),
        totalAmount: _d(j['total_amount']),
      );

  SalesOrderItem copyWith({
    double? qty,
    String? uom,
    double? conversionFactor,
    double? rate,
    double? priceListRate,
    String? deliveryDate,
    String? warehouse,
  }) =>
      SalesOrderItem(
        name: name,
        itemCode: itemCode,
        itemName: itemName,
        qty: qty ?? this.qty,
        uom: uom ?? this.uom,
        stockUom: stockUom,
        conversionFactor: conversionFactor ?? this.conversionFactor,
        rate: rate ?? this.rate,
        priceListRate: priceListRate ?? this.priceListRate,
        amount: (qty ?? this.qty) * (rate ?? this.rate), // provisional; server recomputes
        deliveryDate: deliveryDate ?? this.deliveryDate,
        warehouse: warehouse ?? this.warehouse,
        deliveredQty: deliveredQty,
        deliveredBySupplier: deliveredBySupplier,
        taxAmount: taxAmount,
        totalAmount: totalAmount,
      );
}
