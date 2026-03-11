import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/stock_entry.dart';
import '../repositories/stock_entry_repository.dart';

class SaveStockEntry implements UseCase<StockEntry, StockEntry> {
  final StockEntryRepository repository;

  SaveStockEntry(this.repository);

  @override
  Future<Either<Failure, StockEntry>> call(StockEntry stockEntry) async {
    if (stockEntry.isNew) {
      return await repository.createStockEntry(stockEntry);
    } else {
      return await repository.updateStockEntry(stockEntry);
    }
  }
}
