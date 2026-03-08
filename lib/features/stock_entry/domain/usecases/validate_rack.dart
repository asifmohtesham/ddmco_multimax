import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/stock_entry_repository.dart';

/// Use case for validating warehouse rack
class ValidateRack implements UseCase<bool, ValidateRackParams> {
  final StockEntryRepository repository;

  ValidateRack(this.repository);

  @override
  Future<Either<Failure, bool>> call(ValidateRackParams params) async {
    return await repository.validateRack(
      warehouse: params.warehouse,
      rack: params.rack,
    );
  }
}

class ValidateRackParams {
  final String warehouse;
  final String rack;

  const ValidateRackParams({
    required this.warehouse,
    required this.rack,
  });
}
