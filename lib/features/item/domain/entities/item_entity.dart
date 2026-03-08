import 'package:equatable/equatable.dart';

/// Domain entity for Item
/// Pure business object with no framework dependencies
class ItemEntity extends Equatable {
  final String name;
  final String itemName;
  final String itemCode;
  final String itemGroup;
  final String? image;
  final String? variantOf;
  final String? countryOfOrigin;
  final String? description;
  final String? stockUom;
  final List<ItemAttributeEntity> attributes;
  final List<ItemCustomerDetailEntity> customerItems;

  const ItemEntity({
    required this.name,
    required this.itemName,
    required this.itemCode,
    required this.itemGroup,
    this.image,
    this.variantOf,
    this.countryOfOrigin,
    this.description,
    this.stockUom,
    this.attributes = const [],
    this.customerItems = const [],
  });

  /// Business logic: Check if item is a variant
  bool get isVariant => variantOf != null && variantOf!.isNotEmpty;

  /// Business logic: Check if item is a template (has variants)
  bool get isTemplate => attributes.isNotEmpty;

  /// Business logic: Check if item has customer-specific codes
  bool get hasCustomerItems => customerItems.isNotEmpty;

  /// Business logic: Get customer reference code
  String? getCustomerRefCode(String customerName) {
    try {
      return customerItems
          .firstWhere(
            (item) => item.customerName.toLowerCase() == customerName.toLowerCase(),
          )
          .refCode;
    } catch (_) {
      return null;
    }
  }

  /// Business logic: Check if item has image
  bool get hasImage => image != null && image!.isNotEmpty;

  @override
  List<Object?> get props => [
        name,
        itemName,
        itemCode,
        itemGroup,
        image,
        variantOf,
        countryOfOrigin,
        description,
        stockUom,
        attributes,
        customerItems,
      ];
}

/// Item attribute entity
class ItemAttributeEntity extends Equatable {
  final String attributeName;
  final String attributeValue;

  const ItemAttributeEntity({
    required this.attributeName,
    required this.attributeValue,
  });

  @override
  List<Object?> get props => [attributeName, attributeValue];
}

/// Customer-specific item details
class ItemCustomerDetailEntity extends Equatable {
  final String customerName;
  final String refCode;

  const ItemCustomerDetailEntity({
    required this.customerName,
    required this.refCode,
  });

  @override
  List<Object?> get props => [customerName, refCode];
}

/// Warehouse stock information
class WarehouseStockEntity extends Equatable {
  final String warehouse;
  final double quantity;
  final String? rack;

  const WarehouseStockEntity({
    required this.warehouse,
    required this.quantity,
    this.rack,
  });

  /// Business logic: Check if stock is available
  bool get hasStock => quantity > 0;

  /// Business logic: Check if stock is low (less than 10)
  bool get isLowStock => quantity > 0 && quantity < 10;

  /// Business logic: Check if out of stock
  bool get isOutOfStock => quantity <= 0;

  @override
  List<Object?> get props => [warehouse, quantity, rack];
}

/// Stock ledger entry
class StockLedgerEntity extends Equatable {
  final String postingDate;
  final String postingTime;
  final String warehouse;
  final double actualQty;
  final double qtyAfterTransaction;
  final String voucherType;
  final String voucherNo;
  final String? batchNo;

  const StockLedgerEntity({
    required this.postingDate,
    required this.postingTime,
    required this.warehouse,
    required this.actualQty,
    required this.qtyAfterTransaction,
    required this.voucherType,
    required this.voucherNo,
    this.batchNo,
  });

  /// Business logic: Check if entry is inward (receipt)
  bool get isInward => actualQty > 0;

  /// Business logic: Check if entry is outward (issue)
  bool get isOutward => actualQty < 0;

  @override
  List<Object?> get props => [
        postingDate,
        postingTime,
        warehouse,
        actualQty,
        qtyAfterTransaction,
        voucherType,
        voucherNo,
        batchNo,
      ];
}
