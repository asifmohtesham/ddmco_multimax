import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching stock for a specific warehouse
class GetWarehouseStock
    implements UseCase<List<WarehouseStockEntity>, String> {
  final ItemRepository repository;

  GetWarehouseStock(this.repository);

  @override
  Future<Either<Failure, List<WarehouseStockEntity>>> call(
    String warehouse,
  ) async {
    // Business validation
    if (warehouse.trim().isEmpty) {
      return Either.left(
        ValidationFailure('Warehouse cannot be empty'),
      );
    }

    return await repository.getWarehouseStock(warehouse);
  }
}
