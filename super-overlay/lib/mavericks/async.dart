/// Async state for work such as a network request or database read.
///
/// This follows the official Mavericks pattern of keeping async work in state
/// so a screen stays a pure function of state instead of splitting loading,
/// success, and failure across separate flags or callbacks.
///
/// `Async<T>` has four cases:
/// `Uninitialized`, `Loading(previousValue?)`, `Success(value)`, and
/// `Fail(error, previousValue?)`.
///
/// In this package, `MavericksViewModel.execute` is the standard way to move a
/// state field through those transitions.
sealed class Async<T> {
  const Async();

  T? get valueOrNull;

  Object? get errorOrNull => switch (this) {
    Fail<T>(:final error) => error,
    _ => null,
  };

  bool get isLoading => this is Loading<T>;

  bool get isSuccess => this is Success<T>;

  bool get isFail => this is Fail<T>;

  bool get isUninitialized => this is Uninitialized<T>;

  Async<R> map<R>(R Function(T value) mapper, {bool retainValue = false}) {
    return switch (this) {
      Uninitialized<T>() => Uninitialized<R>(),
      Loading<T>(:final previousValue) => Loading<R>(
        retainValue && previousValue != null ? mapper(previousValue) : null,
      ),
      Success<T>(:final value) => Success<R>(mapper(value)),
      Fail<T>(:final error, :final previousValue) => Fail<R>(
        error,
        retainValue && previousValue != null ? mapper(previousValue) : null,
      ),
    };
  }
}

extension AsyncErrorMessage on Object? {
  String? get messageOrNull {
    final error = this;
    if (error == null) {
      return null;
    }

    if (error is String) {
      return error;
    }

    final dynamicError = error as dynamic;
    final message = dynamicError.message;
    if (message is String && message.isNotEmpty) {
      return message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }
}

final class Uninitialized<T> extends Async<T> {
  const Uninitialized();

  @override
  T? get valueOrNull => null;

  @override
  bool operator ==(Object other) => other is Uninitialized<T>;

  @override
  int get hashCode => 0;
}

final class Loading<T> extends Async<T> {
  const Loading([this.previousValue]);

  final T? previousValue;

  @override
  T? get valueOrNull => previousValue;

  @override
  bool operator ==(Object other) {
    return other is Loading<T> && other.previousValue == previousValue;
  }

  @override
  int get hashCode => Object.hash('loading', previousValue);
}

final class Success<T> extends Async<T> {
  const Success(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  bool operator ==(Object other) {
    return other is Success<T> && other.value == value;
  }

  @override
  int get hashCode => Object.hash('success', value);
}

final class Fail<T> extends Async<T> {
  const Fail(this.error, [this.previousValue]);

  final Object error;
  final T? previousValue;

  @override
  T? get valueOrNull => previousValue;

  @override
  bool operator ==(Object other) {
    return other is Fail<T> &&
        other.error == error &&
        other.previousValue == previousValue;
  }

  @override
  int get hashCode => Object.hash('fail', error, previousValue);
}
