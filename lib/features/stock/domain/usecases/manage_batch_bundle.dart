import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/serial_and_batch_bundle.dart';
import '../repositories/stock_entry_repository.dart';

class ManageBatchBundle implements UseCase<SerialAndBatchBundle, ManageBatchBundleParams> {
  final StockEntryRepository repository;

  ManageBatchBundle(this.repository);

  @override
  Future<Either<Failure, SerialAndBatchBundle>> call(ManageBatchBundleParams params) async {
    if (params.bundle.isNew) {
      return await repository.createBundle(params.bundle);
    } else {
      return await repository.updateBundle(params.bundle);
    }
  }
}

class ManageBatchBundleParams {
  final SerialAndBatchBundle bundle;

  ManageBatchBundleParams(this.bundle);
}
