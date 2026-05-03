import 'package:app/src/features/example/example_todo.dart';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part 'example_api.g.dart';

@RestApi()
abstract class ExampleApi {
  factory ExampleApi(Dio dio, {String? baseUrl}) = _ExampleApi;

  @GET('/todos/1')
  Future<ExampleTodo> getExampleTodo();
}
