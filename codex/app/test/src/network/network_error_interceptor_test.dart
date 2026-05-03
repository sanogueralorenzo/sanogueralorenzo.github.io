import 'dart:typed_data';

import 'package:app/src/network/network_error_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps connection errors to the generic network message', () async {
    final dio = Dio()..interceptors.add(const NetworkErrorInterceptor());
    dio.httpClientAdapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      dio.get('/'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          'Cannot reach the server.',
        ),
      ),
    );
  });

  test('maps 500 responses to the generic server message', () async {
    final dio = Dio()..interceptors.add(const NetworkErrorInterceptor());
    dio.httpClientAdapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 500,
        ),
      ),
    );

    await expectLater(
      dio.get('/'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          'Server error. Try again later.',
        ),
      ),
    );
  });

  test('passes through non-network non-server errors', () async {
    final dio = Dio()..interceptors.add(const NetworkErrorInterceptor());
    dio.httpClientAdapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 404,
        ),
        message: 'keep me',
      ),
    );

    await expectLater(
      dio.get('/'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          'keep me',
        ),
      ),
    );
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final DioException error;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw error.copyWith(requestOptions: options);
  }
}
