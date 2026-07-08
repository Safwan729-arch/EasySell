import 'failure.dart';

/// A lightweight success/failure wrapper returned by every repository method.
///
/// Repositories never throw to controllers; they return a [Result]. Controllers
/// pattern-match on it and surface failures as `AsyncError`.
///
/// ```dart
/// final result = await repo.fetchProducts();
/// return switch (result) {
///   Success(:final value) => value,
///   ResultFailure(:final failure) => throw failure,
/// };
/// ```
sealed class Result<T> {
  const Result();

  /// Convenience constructors.
  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Failure failure) = ResultFailure<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is ResultFailure<T>;

  /// Returns the value or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    ResultFailure<T>() => null,
  };

  /// Folds the result into a single value.
  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    return switch (this) {
      Success<T>(value: final v) => success(v),
      ResultFailure<T>(failure: final f) => failure(f),
    };
  }
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.failure);
  final Failure failure;
}
