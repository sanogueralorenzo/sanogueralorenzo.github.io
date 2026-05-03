import 'package:freezed_annotation/freezed_annotation.dart';

part 'example_todo.freezed.dart';
part 'example_todo.g.dart';

@freezed
abstract class ExampleTodo with _$ExampleTodo {
  const factory ExampleTodo({
    required int id,
    required int userId,
    required String title,
    required bool completed,
  }) = _ExampleTodo;

  factory ExampleTodo.fromJson(Map<String, dynamic> json) =>
      _$ExampleTodoFromJson(json);
}
