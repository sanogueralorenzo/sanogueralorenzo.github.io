import 'dart:io';

import 'package:app/src/features/example/example_api.dart';
import 'package:app/src/features/example/example_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  late HttpServer server;

  setUp(() async {
    server = await shelf_io.serve(
      (shelf.Request request) {
        if (request.url.path == 'todos/1') {
          return shelf.Response.ok(
            '{"id":1,"userId":7,"title":"Load through Retrofit","completed":false}',
            headers: {'content-type': 'application/json'},
          );
        }

        return shelf.Response.notFound('Not found');
      },
      InternetAddress.loopbackIPv4.address,
      0,
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('loads example data through Retrofit API and repository', () async {
    final dio = Dio(
      BaseOptions(baseUrl: 'http://${server.address.host}:${server.port}'),
    );
    final repository = ExampleRepositoryImpl(api: ExampleApi(dio));

    final todo = await repository.getExampleTodo();

    expect(todo.id, 1);
    expect(todo.userId, 7);
    expect(todo.title, 'Load through Retrofit');
    expect(todo.completed, isFalse);
  });
}
