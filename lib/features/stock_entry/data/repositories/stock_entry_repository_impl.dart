import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/entities/stock_entry_entity.dart';
import '../../domain/repositories/stock_entry_repository.dart';
import '../datasources/stock_entry_remote_data_source.dart';
import '../mappers/stock_entry_mapper.dart';

/// Implementation of StockEntryRepository
/// Coordinates between data sources and domain layer
class StockEntryRepositoryImpl implements StockEntryRepository {
  final StockEntryRemoteDataSource remoteDataSource;

  StockEntryRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<StockEntryEntity>>> getStockEntries({
    required int page,
    required int pageSize,
    String? searchQuery,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final models = await remoteDataSource.getStockEntries(
        page: page,
        pageSize: pageSize,
        searchQuery: searchQuery,
        filters: filters,
      );
      return Either.right(StockEntryMapper.toEntityList(models));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, StockEntryEntity>> getStockEntryById(String id) async {
    try {
      final model = await remoteDataSource.getStockEntryById(id);
      return Either.right(StockEntryMapper.toEntity(model));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, StockEntryEntity>> createStockEntry(
    StockEntryEntity stockEntry,
  ) async {
    try {
      final model = StockEntryMapper.toModel(stockEntry);
      final created = await remoteDataSource.createStockEntry(model);
      return Either.right(StockEntryMapper.toEntity(created));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, StockEntryEntity>> updateStockEntry(
    StockEntryEntity stockEntry,
  ) async {
    try {
      final model = StockEntryMapper.toModel(stockEntry);
      final updated = await remoteDataSource.updateStockEntry(model);
      return Either.right(StockEntryMapper.toEntity(updated));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, StockEntryEntity>> submitStockEntry(String id) async {
    try {
      final submitted = await remoteDataSource.submitStockEntry(id);
      return Either.right(StockEntryMapper.toEntity(submitted));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteStockEntry(String id) async {
    try {
      await remoteDataSource.deleteStockEntry(id);
      return Either.right(null);
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } on AuthException catch (e) {
      return Either.left(AuthFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> validateRack({
    required String warehouse,
    required String rack,
  }) async {
    try {
      final isValid = await remoteDataSource.validateRack(
        warehouse: warehouse,
        rack: rack,
      );
      return Either.right(isValid);
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> validateBatch({
    required String itemCode,
    required String warehouse,
    required String batchNo,
  }) async {
    try {
      final result = await remoteDataSource.validateBatch(
        itemCode: itemCode,
        warehouse: warehouse,
        batchNo: batchNo,
      );
      return Either.right(result);
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getBatchWiseBalance({
    required String itemCode,
    required String warehouse,
    String? batchNo,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final results = await remoteDataSource.getBatchWiseBalance(
        itemCode: itemCode,
        warehouse: warehouse,
        batchNo: batchNo,
        fromDate: fromDate,
        toDate: toDate,
      );
      return Either.right(results);
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, SerialBatchBundleEntity>> saveSerialBatchBundle(
    SerialBatchBundleEntity bundle,
  ) async {
    try {
      final model = SerialBatchBundleMapper.toModel(bundle);
      final saved = await remoteDataSource.saveSerialBatchBundle(model);
      return Either.right(SerialBatchBundleMapper.toEntity(saved));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, SerialBatchBundleEntity>> getSerialBatchBundle(
    String bundleId,
  ) async {
    try {
      final model = await remoteDataSource.getSerialBatchBundle(bundleId);
      return Either.right(SerialBatchBundleMapper.toEntity(model));
    } on NetworkException catch (e) {
      return Either.left(NetworkFailure(e.message));
    } on ServerException catch (e) {
      return Either.left(ServerFailure(e.message, e.statusCode));
    } catch (e) {
      return Either.left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }
}
