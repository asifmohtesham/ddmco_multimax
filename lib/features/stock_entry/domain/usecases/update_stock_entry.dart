import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/stock_entry_entity.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for updating an existing stock entry
class UpdateStockEntry implements UseCase<StockEntryEntity, StockEntryEntity> {
  final StockEntryRepository repository;

  UpdateStockEntry(this.repository);

  @override
  Future<Either<Failure, StockEntryEntity>> call(
    StockEntryEntity stockEntry,
  ) async {
    // Business validation
    if (stockEntry.items.isEmpty) {
      return Either.left(
        const ValidationFailure('Stock entry must have at least one item'),
      );
    }

    if (!stockEntry.isDraft) {
      return Either.left(
        const ValidationFailure('Only draft stock entries can be updated'),
      );
    }

    return await repository.updateStockEntry(stockEntry);
  }
}
