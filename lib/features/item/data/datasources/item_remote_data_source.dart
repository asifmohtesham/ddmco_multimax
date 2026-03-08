import '../../../../app/data/models/item_model.dart';

/// Remote data source interface for Item operations
/// This defines the contract for API communication
abstract class ItemRemoteDataSource {
  /// Get paginated list of items
  Future<List<Item>> getItems({
    required int page,
    required int pageSize,
    List<List<dynamic>>? filters,
    String? orderBy,
  });

  /// Get item by item code
  Future<Item> getItemByCode(String itemCode);

  /// Get all item groups
  Future<List<String>> getItemGroups();

  /// Get template items (with variants)
  Future<List<String>> getTemplateItems();

  /// Get all item attributes
  Future<List<String>> getItemAttributes();

  /// Get item attribute details
  Future<Map<String, dynamic>> getItemAttributeDetails(String attributeName);

  /// Get item variants by attribute
  Future<List<String>> getItemVariantsByAttribute(
    String attribute,
    String value,
  );

  /// Get stock levels for an item
  Future<List<WarehouseStock>> getStockLevels(String itemCode);

  /// Get warehouse stock
  Future<List<WarehouseStock>> getWarehouseStock(String warehouse);

  /// Get stock ledger entries
  Future<List<Map<String, dynamic>>> getStockLedger(
    String itemCode, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Get batch-wise balance history
  Future<List<Map<String, dynamic>>> getBatchWiseHistory(String itemCode);
}
