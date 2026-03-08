import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/stock_entry.dart';
import '../entities/serial_and_batch_bundle.dart';

/// Repository interface for Stock Entry operations
abstract class StockEntryRepository {
  /// Get list of stock entries with optional filters
  Future<Either<Failure, List<StockEntry>>> getStockEntries({
    int? limit,
    int? offset,
    String? stockEntryType,
    String? status,
    String? searchQuery,
  });

  /// Get a specific stock entry by name
  Future<Either<Failure, StockEntry>> getStockEntry(String name);

  /// Create a new stock entry
  Future<Either<Failure, StockEntry>> createStockEntry(StockEntry stockEntry);

  /// Update an existing stock entry
  Future<Either<Failure, StockEntry>> updateStockEntry(StockEntry stockEntry);

  /// Delete a stock entry
  Future<Either<Failure, void>> deleteStockEntry(String name);

  /// Submit a stock entry (change docstatus to 1)
  Future<Either<Failure, StockEntry>> submitStockEntry(String name);

  /// Cancel a stock entry (change docstatus to 2)
  Future<Either<Failure, StockEntry>> cancelStockEntry(String name);

  /// Create a serial and batch bundle
  Future<Either<Failure, SerialAndBatchBundle>> createBundle(
    SerialAndBatchBundle bundle,
  );

  /// Update a serial and batch bundle
  Future<Either<Failure, SerialAndBatchBundle>> updateBundle(
    SerialAndBatchBundle bundle,
  );

  /// Get a serial and batch bundle by name
  Future<Either<Failure, SerialAndBatchBundle>> getBundle(String name);

  /// Validate rack for a warehouse
  Future<Either<Failure, bool>> validateRack({
    required String warehouse,
    required String rack,
  });

  /// Validate batch for an item
  Future<Either<Failure, Map<String, dynamic>>> validateBatch({
    required String itemCode,
    required String batchNo,
    required String warehouse,
  });

  /// Search for batches
  Future<Either<Failure, List<Map<String, dynamic>>>> searchBatches({
    required String itemCode,
    required String warehouse,
    String? searchQuery,
  });
}
