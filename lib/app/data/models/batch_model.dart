// app/data/models/batch_model.dart
class Batch {
  final String name;
  final String item;
  final String? description;
  final String? manufacturingDate;
  final String? expiryDate;
  final double customPackagingQty;
  final String? customPurchaseOrder; // Added
  final String creation;
  final String modified;

  Batch({
    required this.name,
    required this.item,
    this.description,
    this.manufacturingDate,
    this.expiryDate,
    this.customPackagingQty = 0.0,
    this.customPurchaseOrder,
    required this.creation,
    required this.modified,
  });

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      name: json['name'] ?? '',
      item: json['item'] ?? '',
      description: json['description'],
      manufacturingDate: json['manufacturing_date'],
      expiryDate: json['expiry_date'],
      customPackagingQty: (json['custom_packaging_qty'] as num?)?.toDouble() ?? 0.0,
      customPurchaseOrder: json['custom_purchase_order'],
      creation: json['creation'] ?? '',
      modified: json['modified'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item': item,
      'description': description,
      'manufacturing_date': manufacturingDate,
      'expiry_date': expiryDate,
      'custom_packaging_qty': customPackagingQty,
      'purchase_order': customPurchaseOrder,
    };
  }
}