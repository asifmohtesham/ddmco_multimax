import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/stock_entry_entity.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for fetching a single stock entry by ID
class GetStockEntryById implements UseCase<StockEntryEntity, String> {
  final StockEntryRepository repository;

  GetStockEntryById(this.repository);

  @override
  Future<Either<Failure, StockEntryEntity>> call(String id) async {
    return await repository.getStockEntryById(id);
  }
}
