import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching a single item by item code
class GetItemByCode implements UseCase<ItemEntity, String> {
  final ItemRepository repository;

  GetItemByCode(this.repository);

  @override
  Future<Either<Failure, ItemEntity>> call(String itemCode) async {
    // Business validation
    if (itemCode.trim().isEmpty) {
      return Either.left(
        ValidationFailure('Item code cannot be empty'),
      );
    }

    return await repository.getItemByCode(itemCode);
  }
}
