import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Local web-only proxy used by `lib/src/network/web_proxy_config.dart`.
///
/// Flutter web debug builds can use this proxy when a browser blocks direct
/// calls to a development API with CORS errors. Prefer enabling direct CORS for
/// the local web origin when the backend supports it.
const _defaultPort = 8080;
const _corsHeaders = <String, String>{
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Accept, Authorization, X-Requested-With',
};

const _hopByHopHeaders = {
  'accept-encoding',
  'connection',
  'content-length',
  'host',
  'transfer-encoding',
};

Future<void> main() async {
  final server = await shelf_io.serve(
    Pipeline().addMiddleware(logRequests()).addHandler(_handleRequest),
    InternetAddress.loopbackIPv4,
    _defaultPort,
  );

  stdout.writeln(
    'Dev web proxy running on http://${server.address.host}:${server.port}',
  );
}

Future<Response> _handleRequest(Request request) async {
  if (request.method == 'OPTIONS') {
    return Response.ok('', headers: _corsHeadersFor(request));
  }

  final targetUri = _targetUri(request.url);
  if (targetUri == null) {
    return Response.notFound('Not found', headers: _corsHeadersFor(request));
  }

  final queryParameters = Map<String, String>.from(request.url.queryParameters);
  final proxyToken = queryParameters.remove('proxy_token');

  final client = HttpClient();
  final outboundRequest = await client.openUrl(
    request.method,
    targetUri.replace(queryParameters: queryParameters),
  );
  outboundRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  request.headers.forEach((name, value) {
    if (_hopByHopHeaders.contains(name.toLowerCase())) {
      return;
    }

    outboundRequest.headers.set(name, value);
  });
  if (proxyToken != null && proxyToken.isNotEmpty) {
    outboundRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $proxyToken',
    );
  }

  final requestBytes = await request.read().fold<BytesBuilder>(
    BytesBuilder(),
    (builder, chunk) => builder..add(chunk),
  );
  outboundRequest.add(requestBytes.takeBytes());

  final outboundResponse = await outboundRequest.close();
  final responseBytes = await _readAllBytes(outboundResponse);
  final responseHeaders = <String, String>{..._corsHeadersFor(request)};

  outboundResponse.headers.forEach((name, values) {
    if (_hopByHopHeaders.contains(name.toLowerCase())) {
      return;
    }

    responseHeaders[name] = values.join(',');
  });

  client.close();

  return Response(
    outboundResponse.statusCode,
    body: responseBytes,
    headers: responseHeaders,
  );
}

Map<String, String> _corsHeadersFor(Request request) {
  final requestedHeaders = request.headers['access-control-request-headers'];
  if (requestedHeaders == null || requestedHeaders.isEmpty) return _corsHeaders;

  return {..._corsHeaders, 'Access-Control-Allow-Headers': requestedHeaders};
}

Uri? _targetUri(Uri requestUrl) {
  final segments = requestUrl.pathSegments;
  if (segments.length < 4 || segments.first != 'proxy') return null;

  final scheme = segments[1];
  final authority = segments[2];
  final pathSegments = segments.sublist(3);
  final authorityUri = Uri.parse('$scheme://$authority');

  return Uri(
    scheme: scheme,
    host: authorityUri.host,
    port: authorityUri.hasPort ? authorityUri.port : null,
    pathSegments: pathSegments,
  );
}

Future<Uint8List> _readAllBytes(HttpClientResponse response) async {
  final builder = BytesBuilder();

  await for (final chunk in response) {
    builder.add(chunk);
  }

  return builder.takeBytes();
}
