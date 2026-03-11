import '../utils/either.dart';
import '../error/failures.dart';

/// Base class for all use cases
/// [Type] is the return type
/// [Params] is the input parameter type
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Used for use cases that don't require parameters
class NoParams {
  const NoParams();
}
