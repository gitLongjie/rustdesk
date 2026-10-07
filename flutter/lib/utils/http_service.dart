import 'package:flutter_hbb/utils/url_launcher.dart' show isOfficialUrl;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:http/http.dart' as http;
import '../models/platform_model.dart';
import 'package:flutter_hbb/common.dart';
export 'package:http/http.dart' show Response;

enum HttpMethod { get, post, put, delete }

class _SelfHostedClient extends http.BaseClient {
  final _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    for (var redirects = 0; ; redirects++) {
      if (isOfficialUrl(request.url)) {
        throw ArgumentError('The official API is disabled');
      }
      request.followRedirects = false;
      final response = await _client.send(request);
      final location = response.headers['location'];
      if (location == null ||
          ![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      await response.stream.drain<void>();
      if (redirects >= 9) throw StateError('Too many redirects');
      final target = request.url.resolve(location);
      final useGet = response.statusCode == 303 ||
          ([301, 302].contains(response.statusCode) && request.method == 'POST');
      final next = http.Request(useGet ? 'GET' : request.method, target);
      next.headers.addAll(request.headers);
      if (target.origin != request.url.origin) {
        next.headers.removeWhere((name, _) =>
            ['authorization', 'cookie'].contains(name.toLowerCase()));
      }
      if (!useGet && request is http.Request) {
        next.bodyBytes = request.bodyBytes;
      }
      request = next;
    }
  }

  @override
  void close() => _client.close();
}

class HttpService {
  Future<http.Response> sendRequest(
    Uri url,
    HttpMethod method, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    if (isOfficialUrl(url)) {
      throw ArgumentError('The official API is disabled');
    }
    headers ??= {'Content-Type': 'application/json'};

    // Use Rust HTTP implementation for non-web platforms for consistency.
    var useFlutterHttp = (isWeb || kIsWeb);
    if (!useFlutterHttp) {
      final enableFlutterHttpOnRust =
          mainGetLocalBoolOptionSync(kOptionEnableFlutterHttpOnRust);
      // Use flutter http if:
      // Not `enableFlutterHttpOnRust` and no proxy is set
      useFlutterHttp =
          !(enableFlutterHttpOnRust || await bind.mainGetProxyStatus());
    }

    if (useFlutterHttp) {
      return await _pollFlutterHttp(url, method, headers: headers, body: body);
    }

    String headersJson = jsonEncode(headers);
    String methodName = method.toString().split('.').last;
    await bind.mainHttpRequest(
        url: url.toString(),
        method: methodName.toLowerCase(),
        body: body,
        header: headersJson);

    var resJson = await _pollForResponse(url.toString());
    return _parseHttpResponse(resJson);
  }

  // Bounds only the pure-Dart branch below, which the OS would otherwise
  // let hang forever (e.g. a black-holed TLS handshake), see #15700.
  // The Rust branch has its own 12s-per-attempt timeouts and must be
  // awaited to completion: a Dart-side timeout there would race the
  // URL-keyed ASYNC_HTTP_STATUS entry of the abandoned request.
  static const _requestTimeout = Duration(seconds: 30);

  Future<http.Response> _pollFlutterHttp(
    Uri url,
    HttpMethod method, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final client = _SelfHostedClient();
    try {
      var response = http.Response('', 400);

      switch (method) {
        case HttpMethod.get:
          response =
              await client.get(url, headers: headers).timeout(_requestTimeout);
          break;
        case HttpMethod.post:
          response = await client
              .post(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        case HttpMethod.put:
          response = await client
              .put(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        case HttpMethod.delete:
          response = await client
              .delete(url, headers: headers, body: body)
              .timeout(_requestTimeout);
          break;
        default:
          throw Exception('Unsupported HTTP method');
      }

      return response;
    } finally {
      client.close();
    }
  }

  Future<String> _pollForResponse(String url) async {
    String? responseJson = " ";
    while (responseJson == " ") {
      responseJson = await bind.mainGetHttpStatus(url: url);
      if (responseJson == null) {
        throw Exception('The HTTP request failed');
      }
      if (responseJson == " ") {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return responseJson!;
  }

  http.Response _parseHttpResponse(String responseJson) {
    try {
      var parsedJson = jsonDecode(responseJson);
      String body = parsedJson['body'];
      Map<String, String> headers = {};
      for (var key in parsedJson['headers'].keys) {
        headers[key] = parsedJson['headers'][key];
      }
      int statusCode = parsedJson['status_code'];
      return http.Response(body, statusCode, headers: headers);
    } catch (e) {
      print('Failed to parse response\n$responseJson\nError:\n$e');
      throw Exception('Failed to parse response.\n$responseJson');
    }
  }
}

Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
  return await HttpService().sendRequest(url, HttpMethod.get, headers: headers);
}

Future<http.Response> post(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.post, body: body, headers: headers);
}

Future<http.Response> put(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.put, body: body, headers: headers);
}

Future<http.Response> delete(Uri url,
    {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
  return await HttpService()
      .sendRequest(url, HttpMethod.delete, body: body, headers: headers);
}
