import 'package:app/src/environments/environments.dart';
import 'package:app/src/network/api_type.dart';
import 'package:app/src/network/network_client_factory.dart';
import 'package:app/src/network/web_proxy_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('api type exposes expected base urls for default qa environment', () {
    expect(Environments.current, AppEnvironment.qa);
    expect(ApiType.example.baseUrl, 'https://jsonplaceholder.typicode.com');
  });

  test('api type exposes expected domain pieces', () {
    expect(ApiType.example.basePath, isEmpty);
    expect(ApiType.example.domain, 'jsonplaceholder.typicode.com');
  });

  test('network client factory configures base options and interceptors', () {
    final interceptor = InterceptorsWrapper();
    final dio = NetworkClientFactory.createDio(
      apiType: ApiType.example,
      interceptors: [interceptor],
    );

    expect(dio.options.baseUrl, 'https://jsonplaceholder.typicode.com');
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.receiveTimeout, const Duration(seconds: 10));
    expect(dio.options.sendTimeout, const Duration(seconds: 10));
    expect(dio.options.headers['Accept'], 'application/json');
    expect(dio.interceptors, contains(interceptor));
    expect(dio.interceptors.any((value) => value is LogInterceptor), isTrue);
  });

  test('web proxy config wraps absolute urls with the local proxy origin', () {
    expect(
      WebProxyConfig.wrapUrl('https://jsonplaceholder.typicode.com/todos/1'),
      'http://localhost:8080/proxy/https/jsonplaceholder.typicode.com/todos/1',
    );
  });
}
