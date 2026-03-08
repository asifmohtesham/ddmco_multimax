/// Result type for cleaner error handling
/// Alternative to Either from dartz for simpler cases
sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Error<T> extends Result<T> {
  final String message;
  final Exception? exception;
  const Error(this.message, [this.exception]);
}

class Loading<T> extends Result<T> {
  const Loading();
}

/// Extension methods for Result
extension ResultExtension<T> on Result<T> {
  bool get isSuccess => this is Success<T>;
  bool get isError => this is Error<T>;
  bool get isLoading => this is Loading<T>;

  T? get dataOrNull => this is Success<T> ? (this as Success<T>).data : null;
  String? get errorOrNull => this is Error<T> ? (this as Error<T>).message : null;

  R when<R>({
    required R Function(T data) success,
    required R Function(String message, Exception? exception) error,
    required R Function() loading,
  }) {
    return switch (this) {
      Success(data: final data) => success(data),
      Error(message: final message, exception: final exception) => error(message, exception),
      Loading() => loading(),
    };
  }
}
