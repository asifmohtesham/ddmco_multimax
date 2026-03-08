import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../domain/entities/item_entity.dart';
import '../../domain/repositories/item_repository.dart';
import '../datasources/item_remote_data_source.dart';
import '../mappers/item_mapper.dart';

/// Implementation of ItemRepository
/// Coordinates between data sources and domain layer
class ItemRepositoryImpl implements ItemRepository {
  final ItemRemoteDataSource remoteDataSource;

  ItemRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<ItemEntity>>> getItems({
    required int page,
    required int pageSize,
    List<List<dynamic>>? filters,
    String? orderBy,
  }) async {
    try {
      final models = await remoteDataSource.getItems(
        page: page,
        pageSize: pageSize,
        filters: filters,
        orderBy: orderBy,
      );
      return Either.right(ItemMapper.toEntityList(models));
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
  Future<Either<Failure, ItemEntity>> getItemByCode(String itemCode) async {
    try {
      final model = await remoteDataSource.getItemByCode(itemCode);
      return Either.right(ItemMapper.toEntity(model));
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
  Future<Either<Failure, List<String>>> getItemGroups() async {
    try {
      final groups = await remoteDataSource.getItemGroups();
      return Either.right(groups);
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
  Future<Either<Failure, List<String>>> getTemplateItems() async {
    try {
      final templates = await remoteDataSource.getTemplateItems();
      return Either.right(templates);
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
  Future<Either<Failure, List<String>>> getItemAttributes() async {
    try {
      final attributes = await remoteDataSource.getItemAttributes();
      return Either.right(attributes);
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
  Future<Either<Failure, Map<String, dynamic>>> getItemAttributeDetails(
    String attributeName,
  ) async {
    try {
      final details = await remoteDataSource.getItemAttributeDetails(attributeName);
      return Either.right(details);
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
  Future<Either<Failure, List<String>>> getItemVariantsByAttribute(
    String attribute,
    String value,
  ) async {
    try {
      final variants = await remoteDataSource.getItemVariantsByAttribute(
        attribute,
        value,
      );
      return Either.right(variants);
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
  Future<Either<Failure, List<WarehouseStockEntity>>> getStockLevels(
    String itemCode,
  ) async {
    try {
      final stocks = await remoteDataSource.getStockLevels(itemCode);
      return Either.right(WarehouseStockMapper.toEntityList(stocks));
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
  Future<Either<Failure, List<WarehouseStockEntity>>> getWarehouseStock(
    String warehouse,
  ) async {
    try {
      final stocks = await remoteDataSource.getWarehouseStock(warehouse);
      return Either.right(WarehouseStockMapper.toEntityList(stocks));
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
  Future<Either<Failure, List<StockLedgerEntity>>> getStockLedger(
    String itemCode, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final ledgers = await remoteDataSource.getStockLedger(
        itemCode,
        fromDate: fromDate,
        toDate: toDate,
      );
      return Either.right(StockLedgerMapper.toEntityList(ledgers));
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
  Future<Either<Failure, List<Map<String, dynamic>>>> getBatchWiseHistory(
    String itemCode,
  ) async {
    try {
      final history = await remoteDataSource.getBatchWiseHistory(itemCode);
      return Either.right(history);
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
}
