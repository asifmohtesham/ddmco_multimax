import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching stock ledger entries
class GetStockLedger
    implements UseCase<List<StockLedgerEntity>, GetStockLedgerParams> {
  final ItemRepository repository;

  GetStockLedger(this.repository);

  @override
  Future<Either<Failure, List<StockLedgerEntity>>> call(
    GetStockLedgerParams params,
  ) async {
    // Business validation
    if (params.itemCode.trim().isEmpty) {
      return Either.left(
        ValidationFailure('Item code cannot be empty'),
      );
    }

    if (params.fromDate != null && params.toDate != null) {
      if (params.fromDate!.isAfter(params.toDate!)) {
        return Either.left(
          ValidationFailure('From date cannot be after to date'),
        );
      }
    }

    return await repository.getStockLedger(
      params.itemCode,
      fromDate: params.fromDate,
      toDate: params.toDate,
    );
  }
}

class GetStockLedgerParams {
  final String itemCode;
  final DateTime? fromDate;
  final DateTime? toDate;

  GetStockLedgerParams({
    required this.itemCode,
    this.fromDate,
    this.toDate,
  });
}
