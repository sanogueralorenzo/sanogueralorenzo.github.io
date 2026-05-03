import 'dart:async';

import 'package:app/src/features/example/example_repository.dart';
import 'package:app/src/features/example/example_todo.dart';
import 'package:app/src/features/example/example_view_model.dart';
import 'package:app/src/mavericks/async.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CompleterExampleRepository implements ExampleRepository {
  final completer = Completer<ExampleTodo>();

  @override
  Future<ExampleTodo> getExampleTodo() => completer.future;
}

void main() {
  test('starts loading example data on creation', () async {
    const todo = ExampleTodo(
      id: 1,
      userId: 2,
      title: 'Exercise the Mavericks flow',
      completed: true,
    );
    final repository = _CompleterExampleRepository();
    final viewModel = ExampleViewModelImpl(repository: repository);
    final states = <ExampleState>[];
    final subscription = viewModel.stream.listen(states.add);

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.state.todo, isA<Loading<ExampleTodo>>());
    expect(states, [viewModel.state]);

    repository.completer.complete(todo);
    await Future<void>.delayed(Duration.zero);

    expect(states.last.todo, const Success(todo));

    await subscription.cancel();
    await viewModel.close();
  });
}
