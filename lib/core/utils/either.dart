/// A functional type that represents a value of one of two possible types
/// [L] represents the Left type (typically used for failures/errors)
/// [R] represents the Right type (typically used for success values)
class Either<L, R> {
  final L? _left;
  final R? _right;
  final bool _isLeft;

  const Either.left(L left)
      : _left = left,
        _right = null,
        _isLeft = true;

  const Either.right(R right)
      : _left = null,
        _right = right,
        _isLeft = false;

  /// Returns true if this is a Left value
  bool get isLeft => _isLeft;

  /// Returns true if this is a Right value
  bool get isRight => !_isLeft;

  /// Returns the Left value or null
  L? get leftOrNull => _left;

  /// Returns the Right value or null
  R? get rightOrNull => _right;

  /// Applies the appropriate function based on whether this is Left or Right
  T fold<T>(T Function(L left) leftFn, T Function(R right) rightFn) {
    return _isLeft ? leftFn(_left as L) : rightFn(_right as R);
  }

  @override
  String toString() {
    return _isLeft ? 'Left($_left)' : 'Right($_right)';
  }
}
