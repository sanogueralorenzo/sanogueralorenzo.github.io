import 'package:app/src/features/example/example_repository.dart';
import 'package:app/src/features/example/example_todo.dart';
import 'package:app/src/mavericks/async.dart';
import 'package:app/src/mavericks/mavericks_state.dart';
import 'package:app/src/mavericks/mavericks_view_model.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'example_view_model.freezed.dart';

@freezed
abstract class ExampleState extends MavericksState<ExampleState>
    with _$ExampleState {
  const ExampleState._() : super();

  const factory ExampleState({
    @Default(Uninitialized<ExampleTodo>()) Async<ExampleTodo> todo,
  }) = _ExampleState;

  ExampleTodo? get loadedTodo => todo.valueOrNull;

  String? get errorMessage => todo.errorOrNull.messageOrNull;
}

abstract class ExampleViewModel extends MavericksViewModel<ExampleState> {
  ExampleViewModel(super.initialState);

  Future<void> load();
}

@Injectable(as: ExampleViewModel)
class ExampleViewModelImpl extends ExampleViewModel {
  ExampleViewModelImpl({required this.repository})
    : super(const ExampleState()) {
    load();
  }

  final ExampleRepository repository;

  @override
  Future<void> load() {
    return execute<ExampleTodo>(
      task: repository.getExampleTodo,
      reducer: (state, async) => state.copyWith(todo: async),
      current: (state) => state.todo,
      retainValue: true,
    );
  }
}
