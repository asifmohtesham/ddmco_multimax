import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching template items (items with variants)
class GetTemplateItems implements UseCase<List<String>, NoParams> {
  final ItemRepository repository;

  GetTemplateItems(this.repository);

  @override
  Future<Either<Failure, List<String>>> call(NoParams params) async {
    return await repository.getTemplateItems();
  }
}
