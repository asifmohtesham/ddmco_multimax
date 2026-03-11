import '../../../../app/data/models/stock_entry_model.dart';
import '../../domain/entities/stock_entry_entity.dart';

/// Mapper to convert between StockEntry model (DTO) and StockEntryEntity (domain)
class StockEntryMapper {
  /// Convert model to entity
  static StockEntryEntity toEntity(StockEntry model) {
    return StockEntryEntity(
      name: model.name,
      purpose: model.purpose,
      totalAmount: model.totalAmount,
      postingDate: model.postingDate,
      modified: model.modified,
      creation: model.creation,
      status: model.status,
      docstatus: model.docstatus,
      owner: model.owner,
      modifiedBy: model.modifiedBy,
      stockEntryType: model.stockEntryType,
      postingTime: model.postingTime,
      fromWarehouse: model.fromWarehouse,
      toWarehouse: model.toWarehouse,
      customTotalQty: model.customTotalQty,
      customReferenceNo: model.customReferenceNo,
      currency: model.currency,
      items: model.items.map(StockEntryItemMapper.toEntity).toList(),
    );
  }

  /// Convert entity to model
  static StockEntry toModel(StockEntryEntity entity) {
    return StockEntry(
      name: entity.name,
      purpose: entity.purpose,
      totalAmount: entity.totalAmount,
      postingDate: entity.postingDate,
      modified: entity.modified,
      creation: entity.creation,
      status: entity.status,
      docstatus: entity.docstatus,
      owner: entity.owner,
      modifiedBy: entity.modifiedBy,
      stockEntryType: entity.stockEntryType,
      postingTime: entity.postingTime,
      fromWarehouse: entity.fromWarehouse,
      toWarehouse: entity.toWarehouse,
      customTotalQty: entity.customTotalQty,
      customReferenceNo: entity.customReferenceNo,
      currency: entity.currency,
      items: entity.items.map(StockEntryItemMapper.toModel).toList(),
    );
  }

  /// Convert list of models to entities
  static List<StockEntryEntity> toEntityList(List<StockEntry> models) {
    return models.map(toEntity).toList();
  }
}

class StockEntryItemMapper {
  static StockEntryItemEntity toEntity(StockEntryItem model) {
    return StockEntryItemEntity(
      name: model.name,
      itemCode: model.itemCode,
      qty: model.qty,
      basicRate: model.basicRate,
      itemGroup: model.itemGroup,
      customVariantOf: model.customVariantOf,
      batchNo: model.batchNo,
      itemName: model.itemName,
      rack: model.rack,
      toRack: model.toRack,
      sWarehouse: model.sWarehouse,
      tWarehouse: model.tWarehouse,
      customInvoiceSerialNumber: model.customInvoiceSerialNumber,
      serialAndBatchBundle: model.serialAndBatchBundle,
      useSerialBatchFields: model.useSerialBatchFields,
      materialRequest: model.materialRequest,
      materialRequestItem: model.materialRequestItem,
    );
  }

  static StockEntryItem toModel(StockEntryItemEntity entity) {
    return StockEntryItem(
      name: entity.name,
      itemCode: entity.itemCode,
      qty: entity.qty,
      basicRate: entity.basicRate,
      itemGroup: entity.itemGroup,
      customVariantOf: entity.customVariantOf,
      batchNo: entity.batchNo,
      itemName: entity.itemName,
      rack: entity.rack,
      toRack: entity.toRack,
      sWarehouse: entity.sWarehouse,
      tWarehouse: entity.tWarehouse,
      customInvoiceSerialNumber: entity.customInvoiceSerialNumber,
      serialAndBatchBundle: entity.serialAndBatchBundle,
      useSerialBatchFields: entity.useSerialBatchFields,
      materialRequest: entity.materialRequest,
      materialRequestItem: entity.materialRequestItem,
    );
  }
}

class SerialBatchBundleMapper {
  static SerialBatchBundleEntity toEntity(SerialAndBatchBundle model) {
    return SerialBatchBundleEntity(
      name: model.name,
      itemCode: model.itemCode,
      warehouse: model.warehouse,
      totalQty: model.totalQty,
      entries: model.entries.map(SerialBatchEntryMapper.toEntity).toList(),
    );
  }

  static SerialAndBatchBundle toModel(SerialBatchBundleEntity entity) {
    return SerialAndBatchBundle(
      name: entity.name,
      itemCode: entity.itemCode,
      warehouse: entity.warehouse,
      totalQty: entity.totalQty,
      entries: entity.entries.map(SerialBatchEntryMapper.toModel).toList(),
    );
  }
}

class SerialBatchEntryMapper {
  static SerialBatchEntryEntity toEntity(SerialAndBatchEntry model) {
    return SerialBatchEntryEntity(
      batchNo: model.batchNo,
      serialNo: model.serialNo,
      qty: model.qty,
    );
  }

  static SerialAndBatchEntry toModel(SerialBatchEntryEntity entity) {
    return SerialAndBatchEntry(
      batchNo: entity.batchNo,
      serialNo: entity.serialNo,
      qty: entity.qty,
    );
  }
}
