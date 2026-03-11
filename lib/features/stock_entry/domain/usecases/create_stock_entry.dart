import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/stock_entry_entity.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for creating a new stock entry
class CreateStockEntry implements UseCase<StockEntryEntity, StockEntryEntity> {
  final StockEntryRepository repository;

  CreateStockEntry(this.repository);

  @override
  Future<Either<Failure, StockEntryEntity>> call(
    StockEntryEntity stockEntry,
  ) async {
    // Business validation can be added here
    if (stockEntry.items.isEmpty) {
      return Either.left(
        const ValidationFailure('Stock entry must have at least one item'),
      );
    }

    return await repository.createStockEntry(stockEntry);
  }
}
