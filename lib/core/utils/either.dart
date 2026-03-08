/// Simple Either implementation for functional error handling
/// This is a temporary implementation until dartz package is added
sealed class Either<L, R> {
  const Either();

  /// Creates a Left value (typically used for failures/errors)
  factory Either.left(L value) = Left<L, R>;

  /// Creates a Right value (typically used for success)
  factory Either.right(R value) = Right<L, R>;

  /// Checks if this is a Left value
  bool get isLeft => this is Left<L, R>;

  /// Checks if this is a Right value
  bool get isRight => this is Right<L, R>;

  /// Folds the Either into a single value
  T fold<T>(T Function(L left) onLeft, T Function(R right) onRight) {
    return switch (this) {
      Left(value: final l) => onLeft(l),
      Right(value: final r) => onRight(r),
    };
  }

  /// Gets the Left value or null
  L? get leftOrNull => fold((l) => l, (_) => null);

  /// Gets the Right value or null
  R? get rightOrNull => fold((_) => null, (r) => r);
}

final class Left<L, R> extends Either<L, R> {
  final L value;
  const Left(this.value);
}

final class Right<L, R> extends Either<L, R> {
  final R value;
  const Right(this.value);
}
