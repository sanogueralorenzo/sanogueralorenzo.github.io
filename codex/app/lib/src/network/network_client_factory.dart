import 'package:app/src/environments/environments.dart';
import 'package:app/src/network/api_type.dart';
import 'package:app/src/network/web_proxy_config.dart';
import 'package:dio/dio.dart';

abstract final class NetworkClientFactory {
  static Dio createDio({
    required ApiType apiType,
    Iterable<Interceptor> interceptors = const [],
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: WebProxyConfig.isEnabled
            ? WebProxyConfig.wrapUrl(apiType.baseUrl)
            : apiType.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: const {'Accept': 'application/json'},
      ),
    );

    dio.interceptors.addAll(interceptors);

    if (!Environments.isProduction) {
      dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true),
      );
    }

    return dio;
  }
}
