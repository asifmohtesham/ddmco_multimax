import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/stock_entry.dart';
import '../repositories/stock_entry_repository.dart';

class SubmitStockEntry implements UseCase<StockEntry, String> {
  final StockEntryRepository repository;

  SubmitStockEntry(this.repository);

  @override
  Future<Either<Failure, StockEntry>> call(String name) async {
    return await repository.submitStockEntry(name);
  }
}
