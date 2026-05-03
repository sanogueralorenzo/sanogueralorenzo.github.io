import 'package:app/src/features/example/example_api.dart';
import 'package:app/src/features/example/example_todo.dart';
import 'package:injectable/injectable.dart';

abstract interface class ExampleRepository {
  Future<ExampleTodo> getExampleTodo();
}

@LazySingleton(as: ExampleRepository)
class ExampleRepositoryImpl implements ExampleRepository {
  const ExampleRepositoryImpl({required this.api});

  final ExampleApi api;

  @override
  Future<ExampleTodo> getExampleTodo() {
    return api.getExampleTodo();
  }
}
