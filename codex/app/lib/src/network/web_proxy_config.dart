import 'package:flutter/foundation.dart';

abstract final class WebProxyConfig {
  static const _proxyOrigin = String.fromEnvironment(
    'WEB_PROXY_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const _proxyPath = '/proxy';

  static bool get isEnabled => kIsWeb && !kReleaseMode;

  static String wrapUrl(
    String url, {
    Map<String, String> extraQueryParameters = const {},
  }) {
    final targetUri = Uri.parse(url);
    final queryParameters = {
      ...targetUri.queryParameters,
      ...extraQueryParameters,
    };
    final proxyUri = Uri.parse(_proxyOrigin).replace(
      pathSegments: [
        ...Uri.parse(
          _proxyOrigin,
        ).pathSegments.where((value) => value.isNotEmpty),
        _proxyPath.replaceFirst('/', ''),
        targetUri.scheme,
        targetUri.authority,
        ...targetUri.pathSegments.where((value) => value.isNotEmpty),
      ],
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );

    return proxyUri.toString();
  }
}
