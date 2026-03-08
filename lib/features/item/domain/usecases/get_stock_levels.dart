import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching stock levels for an item
class GetStockLevels
    implements UseCase<List<WarehouseStockEntity>, String> {
  final ItemRepository repository;

  GetStockLevels(this.repository);

  @override
  Future<Either<Failure, List<WarehouseStockEntity>>> call(
    String itemCode,
  ) async {
    // Business validation
    if (itemCode.trim().isEmpty) {
      return Either.left(
        ValidationFailure('Item code cannot be empty'),
      );
    }

    return await repository.getStockLevels(itemCode);
  }
}
