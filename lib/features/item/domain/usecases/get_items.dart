import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/utils/either.dart';
import '../entities/item_entity.dart';
import '../repositories/item_repository.dart';

/// Use case for fetching paginated list of items
class GetItems implements UseCase<List<ItemEntity>, GetItemsParams> {
  final ItemRepository repository;

  GetItems(this.repository);

  @override
  Future<Either<Failure, List<ItemEntity>>> call(GetItemsParams params) async {
    // Business validation
    if (params.pageSize <= 0) {
      return Either.left(
        ValidationFailure('Page size must be greater than 0'),
      );
    }

    if (params.pageSize > 100) {
      return Either.left(
        ValidationFailure('Page size cannot exceed 100'),
      );
    }

    return await repository.getItems(
      page: params.page,
      pageSize: params.pageSize,
      filters: params.filters,
      orderBy: params.orderBy,
    );
  }
}

class GetItemsParams {
  final int page;
  final int pageSize;
  final List<List<dynamic>>? filters;
  final String? orderBy;

  GetItemsParams({
    required this.page,
    required this.pageSize,
    this.filters,
    this.orderBy,
  });
}
