import 'dart:async';
import 'dart:collection';

import 'package:app/src/mavericks/async.dart';
import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:flutter/foundation.dart';

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

  S get state => _state;

  Stream<S> get stream => _controller.stream;

  bool get isClosed => _isClosed;

  void _emit(S nextState) {
    if (_isClosed) return;
    if (_hasDeliveredState && nextState == _lastDeliveredState) return;

    _lastDeliveredState = nextState;
    _hasDeliveredState = true;
    _controller.add(nextState);
  }

  void _scheduleFlush() {
    if (_isClosed || _isFlushScheduled) return;

    _isFlushScheduled = true;
    scheduleMicrotask(() {
      _isFlushScheduled = false;

      while (_pendingStates.isNotEmpty && !_isClosed) {
        _emit(_pendingStates.removeFirst());
      }
    });
  }

  @protected
  void setState(S Function(S state) reducer) {
    if (_isClosed) return;

    _state = reducer(_state);
    _pendingStates.add(_state);
    _scheduleFlush();
  }

  @protected
  T withState<T>(T Function(S state) selector) {
    return selector(_state);
  }

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
        if (distinct && nextValue == previousValue) return;

        previousValue = nextValue;
        final result = listener(nextValue);
        if (result is Future<void>) {
          unawaited(result);
        }
      }),
    );
  }

  @protected
  void setOnEach<T>(Stream<T> source, S Function(S state, T value) reducer) {
    _subscriptions.add(
      source.listen((value) {
        setState((state) => reducer(state, value));
      }),
    );
  }

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
          if (result is Future<void>) unawaited(result);
        case Fail<T>(:final error):
          final result = onFail?.call(error);
          if (result is Future<void>) unawaited(result);
        case Loading<T>():
        case Uninitialized<T>():
          break;
      }
    }, distinct: distinct);
  }

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

  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    _pendingStates.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _controller.close();
  }
}
