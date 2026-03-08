import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';

/// Repository interface for Item operations
/// Defines the contract for data operations without implementation details
abstract class ItemRepository {
  /// Get paginated list of items with optional filters
  Future<Either<Failure, List<ItemEntity>>> getItems({
    required int page,
    required int pageSize,
    List<List<dynamic>>? filters,
    String? orderBy,
  });

  /// Get item details by item code
  Future<Either<Failure, ItemEntity>> getItemByCode(String itemCode);

  /// Get all item groups
  Future<Either<Failure, List<String>>> getItemGroups();

  /// Get template items (items with variants)
  Future<Either<Failure, List<String>>> getTemplateItems();

  /// Get all item attributes
  Future<Either<Failure, List<String>>> getItemAttributes();

  /// Get item attribute details
  Future<Either<Failure, Map<String, dynamic>>> getItemAttributeDetails(
    String attributeName,
  );

  /// Get item variants by attribute
  Future<Either<Failure, List<String>>> getItemVariantsByAttribute(
    String attribute,
    String value,
  );

  /// Get stock levels for an item across all warehouses
  Future<Either<Failure, List<WarehouseStockEntity>>> getStockLevels(
    String itemCode,
  );

  /// Get warehouse stock for a specific warehouse
  Future<Either<Failure, List<WarehouseStockEntity>>> getWarehouseStock(
    String warehouse,
  );

  /// Get stock ledger entries for an item
  Future<Either<Failure, List<StockLedgerEntity>>> getStockLedger(
    String itemCode, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Get batch-wise balance history
  Future<Either<Failure, List<Map<String, dynamic>>>> getBatchWiseHistory(
    String itemCode,
  );
}
