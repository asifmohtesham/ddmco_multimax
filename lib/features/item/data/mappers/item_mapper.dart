import '../../../../app/data/models/item_model.dart';
import '../../domain/entities/item_entity.dart';

/// Mapper to convert between Item model (DTO) and ItemEntity (domain)
class ItemMapper {
  /// Convert model to entity
  static ItemEntity toEntity(Item model) {
    return ItemEntity(
      name: model.name,
      itemName: model.itemName,
      itemCode: model.itemCode,
      itemGroup: model.itemGroup,
      image: model.image,
      variantOf: model.variantOf,
      countryOfOrigin: model.countryOfOrigin,
      description: model.description,
      stockUom: model.stockUom,
      attributes: model.attributes
          .map(ItemAttributeMapper.toEntity)
          .toList(),
      customerItems: model.customerItems
          .map(ItemCustomerDetailMapper.toEntity)
          .toList(),
    );
  }

  /// Convert entity to model
  static Item toModel(ItemEntity entity) {
    return Item(
      name: entity.name,
      itemName: entity.itemName,
      itemCode: entity.itemCode,
      itemGroup: entity.itemGroup,
      image: entity.image,
      variantOf: entity.variantOf,
      countryOfOrigin: entity.countryOfOrigin,
      description: entity.description,
      stockUom: entity.stockUom,
      attributes: entity.attributes
          .map(ItemAttributeMapper.toModel)
          .toList(),
      customerItems: entity.customerItems
          .map(ItemCustomerDetailMapper.toModel)
          .toList(),
    );
  }

  /// Convert list of models to entities
  static List<ItemEntity> toEntityList(List<Item> models) {
    return models.map(toEntity).toList();
  }
}

/// Mapper for ItemAttribute
class ItemAttributeMapper {
  static ItemAttributeEntity toEntity(ItemAttribute model) {
    return ItemAttributeEntity(
      attributeName: model.attributeName,
      attributeValue: model.attributeValue,
    );
  }

  static ItemAttribute toModel(ItemAttributeEntity entity) {
    return ItemAttribute(
      attributeName: entity.attributeName,
      attributeValue: entity.attributeValue,
    );
  }
}

/// Mapper for ItemCustomerDetail
class ItemCustomerDetailMapper {
  static ItemCustomerDetailEntity toEntity(ItemCustomerDetail model) {
    return ItemCustomerDetailEntity(
      customerName: model.customerName,
      refCode: model.refCode,
    );
  }

  static ItemCustomerDetail toModel(ItemCustomerDetailEntity entity) {
    return ItemCustomerDetail(
      customerName: entity.customerName,
      refCode: entity.refCode,
    );
  }
}

/// Mapper for WarehouseStock
class WarehouseStockMapper {
  static WarehouseStockEntity toEntity(WarehouseStock model) {
    return WarehouseStockEntity(
      warehouse: model.warehouse,
      quantity: model.quantity,
      rack: model.rack,
    );
  }

  static WarehouseStock toModel(WarehouseStockEntity entity) {
    return WarehouseStock(
      warehouse: entity.warehouse,
      quantity: entity.quantity,
      rack: entity.rack,
    );
  }

  static List<WarehouseStockEntity> toEntityList(List<WarehouseStock> models) {
    return models.map(toEntity).toList();
  }
}

/// Mapper for StockLedger entries
class StockLedgerMapper {
  static StockLedgerEntity toEntity(Map<String, dynamic> json) {
    return StockLedgerEntity(
      postingDate: json['posting_date'] ?? '',
      postingTime: json['posting_time'] ?? '',
      warehouse: json['warehouse'] ?? '',
      actualQty: (json['actual_qty'] as num?)?.toDouble() ?? 0.0,
      qtyAfterTransaction:
          (json['qty_after_transaction'] as num?)?.toDouble() ?? 0.0,
      voucherType: json['voucher_type'] ?? '',
      voucherNo: json['voucher_no'] ?? '',
      batchNo: json['batch_no'],
    );
  }

  static List<StockLedgerEntity> toEntityList(List<dynamic> jsonList) {
    return jsonList
        .map((json) => toEntity(json as Map<String, dynamic>))
        .toList();
  }
}
