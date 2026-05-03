import 'package:dio/dio.dart';

class NetworkErrorInterceptor extends Interceptor {
  const NetworkErrorInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_isConnectionError(err)) {
      handler.reject(err.copyWith(message: 'Cannot reach the server.'));
      return;
    }

    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500) {
      handler.reject(err.copyWith(message: 'Server error. Try again later.'));
      return;
    }

    handler.next(err);
  }

  bool _isConnectionError(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout;
  }
}
