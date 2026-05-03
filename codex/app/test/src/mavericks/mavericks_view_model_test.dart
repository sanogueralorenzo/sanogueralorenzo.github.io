import 'dart:async';

import 'package:app/src/mavericks/async.dart';
import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:app/src/mavericks/mavericks_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withState sees queued updates and close is idempotent', () async {
    final viewModel = _TestViewModel();
    final states = <_TestState>[];
    final subscription = viewModel.stream.listen(states.add);

    expect(viewModel.isClosed, isFalse);
    expect(viewModel.currentCount(), 0);

    viewModel.setCount(1);
    expect(viewModel.currentCount(), 1);

    await _flushMicrotasks();
    expect(states.map((state) => state.count), [1]);

    await viewModel.close();
    expect(viewModel.isClosed, isTrue);

    viewModel.setCount(2);
    await _flushMicrotasks();
    expect(states.map((state) => state.count), [1]);

    await viewModel.close();
    await subscription.cancel();
  });

  test(
    'flush recurses for reentrant state updates and skips duplicates',
    () async {
      final viewModel = _TestViewModel();
      final emittedCounts = <int>[];
      var queuedSecondState = false;

      final subscription = viewModel.stream.listen((state) {
        emittedCounts.add(state.count);
        if (!queuedSecondState && state.count == 1) {
          queuedSecondState = true;
          viewModel.setCount(2);
        }
      });

      viewModel.setCount(1);
      await _flushMicrotasks();

      expect(emittedCounts, [1, 2]);

      viewModel.setCount(2);
      await _flushMicrotasks();

      expect(emittedCounts, [1, 2]);

      await subscription.cancel();
      await viewModel.close();
    },
  );

  test('onEach runs initial listener and handles distinct delivery', () async {
    final viewModel = _TestViewModel();
    final distinctValues = <int>[];
    final allValues = <int>[];

    viewModel.observeCount((value) async => distinctValues.add(value));
    viewModel.observeCount(
      (value) async => allValues.add(value),
      distinct: false,
    );

    await _flushMicrotasks();
    expect(distinctValues, [0]);
    expect(allValues, [0]);

    viewModel.setCount(0);
    await _flushMicrotasks();
    expect(distinctValues, [0]);
    expect(allValues, [0, 0]);

    viewModel.setCount(3);
    await _flushMicrotasks();
    expect(distinctValues, [0, 3]);
    expect(allValues, [0, 0, 3]);

    await viewModel.close();
  });

  test('onAsync only reacts to success and failure states', () async {
    final viewModel = _TestViewModel();
    final successes = <int>[];
    final failures = <Object>[];

    viewModel.observeAsync(
      onSuccess: (value) async => successes.add(value),
      onFail: (error) async => failures.add(error),
    );

    await _flushMicrotasks();
    expect(successes, isEmpty);
    expect(failures, isEmpty);

    viewModel.setRequest(const Loading<int>());
    await _flushMicrotasks();
    expect(successes, isEmpty);
    expect(failures, isEmpty);

    viewModel.setRequest(const Success<int>(4));
    await _flushMicrotasks();
    expect(successes, [4]);
    expect(failures, isEmpty);

    viewModel.setRequest(const Fail<int>('boom'));
    await _flushMicrotasks();
    expect(successes, [4]);
    expect(failures, ['boom']);

    await viewModel.close();
  });

  test('setOnEach reduces external stream values and auto-disposes', () async {
    final controller = StreamController<int>();
    final viewModel = _TestViewModel();
    final states = <_TestState>[];
    final subscription = viewModel.stream.listen(states.add);

    viewModel.bindExternalCount(controller.stream);

    controller.add(2);
    await _flushMicrotasks();
    expect(states.map((state) => state.count), [2]);

    await viewModel.close();

    controller.add(4);
    await _flushMicrotasks();
    expect(states.map((state) => state.count), [2]);

    await subscription.cancel();
    await controller.close();
  });

  test(
    'execute emits success and failure states with retained value',
    () async {
      final viewModel = _TestViewModel();
      final requests = <Async<int>>[];
      final subscription = viewModel.stream.listen((state) {
        requests.add(state.request);
      });

      await viewModel.executeSuccess();
      await _flushMicrotasks();

      expect(requests[0], const Loading<int>());
      expect(requests[1], const Success<int>(10));

      viewModel.setRequest(const Success<int>(11));
      await _flushMicrotasks();

      await viewModel.executeFailureWithRetainedValue();
      await _flushMicrotasks();

      expect(requests[2], const Success<int>(11));
      expect(requests[3], const Loading<int>(11));
      expect(requests[4], const Fail<int>('boom', 11));

      await subscription.cancel();
      await viewModel.close();
    },
  );
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _TestViewModel extends MavericksViewModel<_TestState> {
  _TestViewModel() : super(const _TestState());

  int currentCount() {
    return withState((state) => state.count);
  }

  void observeCount(
    Future<void> Function(int value) listener, {
    bool distinct = true,
  }) {
    onEach((state) => state.count, listener, distinct: distinct);
  }

  void observeAsync({
    Future<void> Function(int value)? onSuccess,
    Future<void> Function(Object error)? onFail,
  }) {
    onAsync((state) => state.request, onSuccess: onSuccess, onFail: onFail);
  }

  void bindExternalCount(Stream<int> countStream) {
    setOnEach<int>(countStream, (state, count) => state.copyWith(count: count));
  }

  Future<void> executeSuccess() {
    return execute<int>(
      task: () async => 10,
      reducer: (state, request) => state.copyWith(request: request),
    );
  }

  Future<void> executeFailureWithRetainedValue() {
    return execute<int>(
      task: () async => throw 'boom',
      reducer: (state, request) => state.copyWith(request: request),
      current: (state) => state.request,
      retainValue: true,
    );
  }

  void setCount(int count) {
    setState((state) => state.copyWith(count: count));
  }

  void setRequest(Async<int> request) {
    setState((state) => state.copyWith(request: request));
  }
}

class _TestState extends MavericksState<_TestState> {
  const _TestState({this.count = 0, this.request = const Uninitialized<int>()});

  final int count;
  final Async<int> request;

  _TestState copyWith({int? count, Async<int>? request}) {
    return _TestState(
      count: count ?? this.count,
      request: request ?? this.request,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _TestState &&
        other.count == count &&
        other.request == request;
  }

  @override
  int get hashCode => Object.hash(count, request);
}
