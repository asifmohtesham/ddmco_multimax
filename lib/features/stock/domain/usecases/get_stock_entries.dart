import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/stock_entry.dart';
import '../repositories/stock_entry_repository.dart';

class GetStockEntries implements UseCase<List<StockEntry>, GetStockEntriesParams> {
  final StockEntryRepository repository;

  GetStockEntries(this.repository);

  @override
  Future<Either<Failure, List<StockEntry>>> call(GetStockEntriesParams params) async {
    return await repository.getStockEntries(
      limit: params.limit,
      offset: params.offset,
      stockEntryType: params.stockEntryType,
      status: params.status,
      searchQuery: params.searchQuery,
    );
  }
}

class GetStockEntriesParams {
  final int? limit;
  final int? offset;
  final String? stockEntryType;
  final String? status;
  final String? searchQuery;

  GetStockEntriesParams({
    this.limit,
    this.offset,
    this.stockEntryType,
    this.status,
    this.searchQuery,
  });
}
