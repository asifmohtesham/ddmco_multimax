class PurchaseOrder {
  final String name;
  final String supplier;
  final String transactionDate;
  final double grandTotal;
  final String currency;
  final String status;

  PurchaseOrder({
    required this.name,
    required this.supplier,
    required this.transactionDate,
    required this.grandTotal,
    required this.currency,
    required this.status,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      name: json['name'] ?? '',
      supplier: json['supplier'] ?? '',
      transactionDate: json['transaction_date'] ?? '',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? '',
    );
  }
}
