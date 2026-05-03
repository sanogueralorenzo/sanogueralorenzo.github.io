// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'example_todo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExampleTodo _$ExampleTodoFromJson(Map<String, dynamic> json) => _ExampleTodo(
  id: (json['id'] as num).toInt(),
  userId: (json['userId'] as num).toInt(),
  title: json['title'] as String,
  completed: json['completed'] as bool,
);

Map<String, dynamic> _$ExampleTodoToJson(_ExampleTodo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'title': instance.title,
      'completed': instance.completed,
    };
