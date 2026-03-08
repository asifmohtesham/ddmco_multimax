import '../../../../app/data/models/stock_entry_model.dart';

/// Remote data source interface for Stock Entry
/// This defines the contract for API communication
abstract class StockEntryRemoteDataSource {
  /// Get paginated list of stock entries
  Future<List<StockEntry>> getStockEntries({
    required int page,
    required int pageSize,
    String? searchQuery,
    Map<String, dynamic>? filters,
  });

  /// Get a single stock entry by ID
  Future<StockEntry> getStockEntryById(String id);

  /// Create a new stock entry
  Future<StockEntry> createStockEntry(StockEntry stockEntry);

  /// Update an existing stock entry
  Future<StockEntry> updateStockEntry(StockEntry stockEntry);

  /// Submit a stock entry
  Future<StockEntry> submitStockEntry(String id);

  /// Delete a stock entry
  Future<void> deleteStockEntry(String id);

  /// Validate warehouse rack
  Future<bool> validateRack({
    required String warehouse,
    required String rack,
  });

  /// Validate batch availability
  Future<Map<String, dynamic>> validateBatch({
    required String itemCode,
    required String warehouse,
    required String batchNo,
  });

  /// Get batch-wise balance
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    required String warehouse,
    String? batchNo,
    required DateTime fromDate,
    required DateTime toDate,
  });

  /// Create or update serial and batch bundle
  Future<SerialAndBatchBundle> saveSerialBatchBundle(
    SerialAndBatchBundle bundle,
  );

  /// Get serial and batch bundle by ID
  Future<SerialAndBatchBundle> getSerialBatchBundle(String bundleId);
}
