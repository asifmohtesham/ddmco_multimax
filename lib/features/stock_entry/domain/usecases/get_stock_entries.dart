import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/stock_entry_entity.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for fetching paginated stock entries
class GetStockEntries implements UseCase<List<StockEntryEntity>, GetStockEntriesParams> {
  final StockEntryRepository repository;

  GetStockEntries(this.repository);

  @override
  Future<Either<Failure, List<StockEntryEntity>>> call(
    GetStockEntriesParams params,
  ) async {
    return await repository.getStockEntries(
      page: params.page,
      pageSize: params.pageSize,
      searchQuery: params.searchQuery,
      filters: params.filters,
    );
  }
}

class GetStockEntriesParams {
  final int page;
  final int pageSize;
  final String? searchQuery;
  final Map<String, dynamic>? filters;

  const GetStockEntriesParams({
    required this.page,
    required this.pageSize,
    this.searchQuery,
    this.filters,
  });
}
