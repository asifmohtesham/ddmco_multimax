import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching all item attributes
class GetItemAttributes implements UseCase<List<String>, NoParams> {
  final ItemRepository repository;

  GetItemAttributes(this.repository);

  @override
  Future<Either<Failure, List<String>>> call(NoParams params) async {
    return await repository.getItemAttributes();
  }
}
