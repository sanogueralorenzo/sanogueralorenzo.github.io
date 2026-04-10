import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_overlay/mavericks/async.dart';
import 'package:super_overlay/mavericks/mavericks_state.dart';

/// Base class for Mavericks-style view models backed by a single immutable
/// state.
///
/// Like official Mavericks, a view model owns screen state, exposes named
/// actions that reduce that state, and lets other code subscribe to updates.
///
/// Example:
///
/// ```dart
/// abstract class LoginViewModel extends MavericksViewModel<LoginState> {
///   LoginViewModel(super.initialState);
///
///   void updateEmail(String email);
///
///   void updatePassword(String password);
///
///   void togglePasswordVisibility();
///
///   Future<void> login();
/// }
///
/// class LoginViewModelImpl extends LoginViewModel {
///   LoginViewModelImpl({required UserRepository userRepository})
///       : _userRepository = userRepository,
///         super(const LoginState());
///
///   final UserRepository _userRepository;
///
///   @override
///   void updateEmail(String email) {
///     setState((state) => state.copyWith(email: email));
///   }
///
///   @override
///   void updatePassword(String password) {
///     setState((state) => state.copyWith(password: password));
///   }
///
///   @override
///   void togglePasswordVisibility() {
///     setState(
///           (state) => state.copyWith(
///         isPasswordVisible: !state.isPasswordVisible,
///       ),
///     );
///   }
///
///   @override
///   Future<void> login() {
///     final email = state.email;
///     final password = state.password;
///
///     return execute<User>(
///       task: () => _userRepository.login(email: email, password: password),
///       reducer: (state, async) => state.copyWith(loginRequest: async),
///     );
///   }
/// }
/// ```
abstract class MavericksViewModel<S extends MavericksState<S>> {
  MavericksViewModel(S initialState) : _state = initialState;

  final StreamController<S> _controller = StreamController<S>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Queue<S> _pendingStates = Queue<S>();
  S _state;
  var _hasDeliveredState = false;
  var _isFlushScheduled = false;
  var _isClosed = false;
  S? _lastDeliveredState;

  /// Returns the latest state snapshot synchronously.
  ///
  /// Example:
  /// ```dart
  /// final email = state.email;
  /// ```
  S get state {
    return _state;
  }

  /// Emits all future state updates for listeners and builders.
  ///
  /// Example:
  /// ```dart
  /// final subscription = stream.listen(print);
  /// ```
  Stream<S> get stream => _controller.stream;

  /// Returns `true` after [close] has been called.
  ///
  /// Example:
  /// ```dart
  /// if (isClosed) return;
  /// ```
  bool get isClosed => _isClosed;

  /// Delivers a new state internally and skips duplicate deliveries after the
  /// first emission when the new state is equal to the current state.
  void _emit(S nextState) {
    if (_isClosed) {
      return;
    }

    if (_hasDeliveredState && nextState == _lastDeliveredState) {
      return;
    }

    _lastDeliveredState = nextState;
    _hasDeliveredState = true;
    _controller.add(nextState);
  }

  /// Flushes queued state updates in order.
  ///
  /// Like Mavericks reducers, updates are serialized instead of being applied
  /// inline at the call site.
  void _scheduleFlush() {
    if (_isClosed || _isFlushScheduled) {
      return;
    }

    _isFlushScheduled = true;
    scheduleMicrotask(() {
      _isFlushScheduled = false;

      while (_pendingStates.isNotEmpty && !_isClosed) {
        _emit(_pendingStates.removeFirst());
      }
    });
  }

  /// Queues a state update by deriving the next value from the latest state.
  ///
  /// Example:
  /// ```dart
  /// setState((state) => state.copyWith(email: email));
  /// ```
  ///
  /// Like `setState { copy(...) }` in official Mavericks, the reducer should
  /// derive the next state from the value passed into the closure rather than a
  /// stale snapshot captured outside of it.
  ///
  /// Example:
  /// ```dart
  /// setState((state) => state.copyWith(email: 'mario@example.com'));
  /// final email = withState((state) => state.email);
  /// ```
  @protected
  void setState(S Function(S state) reducer) {
    if (_isClosed) {
      return;
    }

    final currentState = _state;
    final nextState = reducer(currentState);
    _state = nextState;
    _pendingStates.add(_state);
    _scheduleFlush();
  }

  /// Reads a value from the latest state snapshot without subscribing.
  ///
  /// Example:
  /// ```dart
  /// final email = withState((state) => state.email);
  /// ```
  ///
  /// This is the Flutter equivalent of reading a stable state snapshot once
  /// with `withState`.
  ///
  /// Example:
  /// ```dart
  /// setState((state) => state.copyWith(email: 'mario@example.com'));
  /// final email = withState((state) => state.email);
  /// ```
  @protected
  T withState<T>(T Function(S state) selector) {
    return selector(_state);
  }

  /// Runs [listener] for the selected part of state immediately and on future
  /// updates.
  ///
  /// Example:
  /// ```dart
  /// onEach(
  ///   (state) => state.email,
  ///   (email) => _analytics.logEmailChanged(email),
  /// );
  /// ```
  ///
  /// This mirrors the official Mavericks `onEach` subscription pattern.
  ///
  /// The listener runs immediately with the current selected value and then on
  /// future updates.
  ///
  /// Example:
  /// ```dart
  /// onEach(
  ///   (state) => state.email,
  ///   _prefillForm,
  /// );
  /// ```
  ///
  /// When [distinct] is `true`, equal consecutive values are skipped, similar
  /// to using `uniqueOnly()` delivery in official Mavericks subscriptions.
  ///
  /// Example:
  /// ```dart
  /// onEach(
  ///   (state) => state.searchQuery,
  ///   _trackSearch,
  ///   distinct: false,
  /// );
  /// ```
  @protected
  void onEach<T>(
    T Function(S state) selector,
    FutureOr<void> Function(T value) listener, {
    bool distinct = true,
  }) {
    var previousValue = selector(state);

    final initialResult = listener(previousValue);
    if (initialResult is Future<void>) {
      unawaited(initialResult);
    }

    _subscriptions.add(
      stream.listen((nextState) {
        final nextValue = selector(nextState);
        if (distinct && nextValue == previousValue) {
          return;
        }

        previousValue = nextValue;
        final result = listener(nextValue);
        if (result is Future<void>) {
          unawaited(result);
        }
      }),
    );
  }

  /// Subscribes to an external stream and reduces each emitted value into
  /// state.
  ///
  /// Example:
  /// ```dart
  /// setOnEach<String>(
  ///   repository.emailStream,
  ///   (state, email) => state.copyWith(email: email),
  /// );
  /// ```
  ///
  /// The subscription is owned by the view model and is canceled
  /// automatically in [close].
  @protected
  void setOnEach<T>(
    Stream<T> source,
    S Function(S state, T value) reducer,
  ) {
    _subscriptions.add(
      source.listen((value) {
        setState((state) => reducer(state, value));
      }),
    );
  }

  /// Runs async-specific callbacks whenever the selected [Async] value changes.
  ///
  /// Example:
  /// ```dart
  /// onAsync<User>(
  ///   (state) => state.loginRequest,
  ///   onSuccess: (user) => _analytics.logLoginSuccess(user.id),
  ///   onFail: (error) => _analytics.logLoginFailure(error),
  /// );
  /// ```
  ///
  /// This matches the common Mavericks pattern of reacting to success and
  /// failure separately from normal rendering.
  @protected
  void onAsync<T>(
    Async<T> Function(S state) selector, {
    FutureOr<void> Function(T value)? onSuccess,
    FutureOr<void> Function(Object error)? onFail,
    bool distinct = true,
  }) {
    onEach<Async<T>>(selector, (async) {
      switch (async) {
        case Success<T>(:final value):
          final result = onSuccess?.call(value);
          if (result is Future<void>) {
            unawaited(result);
          }
        case Fail<T>(:final error):
          final result = onFail?.call(error);
          if (result is Future<void>) {
            unawaited(result);
          }
        case Loading<T>():
        case Uninitialized<T>():
          break;
      }
    }, distinct: distinct);
  }

  /// Runs async work and automatically reduces the selected state field through
  /// `Loading`, `Success`, and `Fail`.
  ///
  /// Example:
  /// ```dart
  /// execute<User>(
  ///   task: () => _userRepository.login(email: state.email, password: state.password),
  ///   reducer: (state, async) => state.copyWith(loginRequest: async),
  /// );
  /// ```
  ///
  /// This mirrors the official Mavericks `execute` pattern: kick off the work,
  /// reduce a loading state, then reduce success or failure back into state.
  ///
  /// Use [current] together with [retainValue] to preserve the previous success
  /// value while reloading or failing.
  ///
  /// Example:
  /// ```dart
  /// execute<User>(
  ///   task: _userRepository.refreshUser,
  ///   reducer: (state, async) => state.copyWith(userRequest: async),
  ///   current: (state) => state.userRequest,
  ///   retainValue: true,
  /// );
  /// ```
  @protected
  Future<void> execute<T>({
    required Future<T> Function() task,
    required S Function(S state, Async<T> async) reducer,
    Async<T> Function(S state)? current,
    bool retainValue = false,
  }) async {
    final previousValue = retainValue && current != null
        ? current(state).valueOrNull
        : null;
    setState((state) => reducer(state, Loading<T>(previousValue)));

    try {
      final value = await task();
      setState((state) => reducer(state, Success<T>(value)));
    } catch (error) {
      setState((state) => reducer(state, Fail<T>(error, previousValue)));
    }
  }

  /// Cancels internal subscriptions and closes the state stream.
  ///
  /// Example:
  /// ```dart
  /// await viewModel.close();
  /// ```
  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _pendingStates.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _controller.close();
  }
}
