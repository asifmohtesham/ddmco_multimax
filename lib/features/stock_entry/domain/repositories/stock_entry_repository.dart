import '../../../../core/utils/either.dart';
import '../../../../core/error/failures.dart';
import '../entities/stock_entry_entity.dart';

/// Repository interface for Stock Entry operations
/// This defines the contract that the data layer must implement
abstract class StockEntryRepository {
  /// Get paginated list of stock entries
  Future<Either<Failure, List<StockEntryEntity>>> getStockEntries({
    required int page,
    required int pageSize,
    String? searchQuery,
    Map<String, dynamic>? filters,
  });

  /// Get a single stock entry by ID
  Future<Either<Failure, StockEntryEntity>> getStockEntryById(String id);

  /// Create a new stock entry
  Future<Either<Failure, StockEntryEntity>> createStockEntry(
    StockEntryEntity stockEntry,
  );

  /// Update an existing stock entry
  Future<Either<Failure, StockEntryEntity>> updateStockEntry(
    StockEntryEntity stockEntry,
  );

  /// Submit a stock entry (change from draft to submitted)
  Future<Either<Failure, StockEntryEntity>> submitStockEntry(String id);

  /// Delete a stock entry
  Future<Either<Failure, void>> deleteStockEntry(String id);

  /// Validate warehouse rack
  Future<Either<Failure, bool>> validateRack({
    required String warehouse,
    required String rack,
  });

  /// Validate batch availability
  Future<Either<Failure, Map<String, dynamic>>> validateBatch({
    required String itemCode,
    required String warehouse,
    required String batchNo,
  });

  /// Get batch-wise balance for item
  Future<Either<Failure, List<Map<String, dynamic>>>> getBatchWiseBalance({
    required String itemCode,
    required String warehouse,
    String? batchNo,
    required DateTime fromDate,
    required DateTime toDate,
  });

  /// Create or update serial and batch bundle
  Future<Either<Failure, SerialBatchBundleEntity>> saveSerialBatchBundle(
    SerialBatchBundleEntity bundle,
  );

  /// Get serial and batch bundle by ID
  Future<Either<Failure, SerialBatchBundleEntity>> getSerialBatchBundle(
    String bundleId,
  );
}
