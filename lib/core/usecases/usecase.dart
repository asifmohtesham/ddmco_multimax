import 'package:dartz/dartz.dart';
import '../error/failures.dart';

/// Base class for all use cases
/// 
/// [Type] is the return type of the use case
/// [Params] is the parameters type for the use case
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Use case with no parameters
class NoParams {
  const NoParams();
}

/// Base class for synchronous use cases
abstract class SyncUseCase<Type, Params> {
  Either<Failure, Type> call(Params params);
}

/// Base class for stream-based use cases
abstract class StreamUseCase<Type, Params> {
  Stream<Either<Failure, Type>> call(Params params);
}
