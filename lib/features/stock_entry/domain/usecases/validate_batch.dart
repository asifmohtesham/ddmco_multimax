import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for validating batch availability
class ValidateBatch implements UseCase<Map<String, dynamic>, ValidateBatchParams> {
  final StockEntryRepository repository;

  ValidateBatch(this.repository);

  @override
  Future<Either<Failure, Map<String, dynamic>>> call(
    ValidateBatchParams params,
  ) async {
    return await repository.validateBatch(
      itemCode: params.itemCode,
      warehouse: params.warehouse,
      batchNo: params.batchNo,
    );
  }
}

class ValidateBatchParams {
  final String itemCode;
  final String warehouse;
  final String batchNo;

  const ValidateBatchParams({
    required this.itemCode,
    required this.warehouse,
    required this.batchNo,
  });
}
