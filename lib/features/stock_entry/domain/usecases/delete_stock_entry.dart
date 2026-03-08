import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for deleting a stock entry
class DeleteStockEntry implements UseCase<void, String> {
  final StockEntryRepository repository;

  DeleteStockEntry(this.repository);

  @override
  Future<Either<Failure, void>> call(String id) async {
    return await repository.deleteStockEntry(id);
  }
}
