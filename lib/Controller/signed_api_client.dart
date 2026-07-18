import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../Common/merchant_service_config.dart';

class AppException implements Exception {
  const AppException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() =>
      'AppException: $message${statusCode == null ? '' : ' ($statusCode)'}';
}

class SignedApiClient {
  SignedApiClient({
    this.baseUrl = MerchantServiceConfig.baseUrl,
    this.clientId = MerchantServiceConfig.clientId,
    this.hmacSecretKey = MerchantServiceConfig.hmacSecretKey,
    http.Client? httpClient,
    this.onAuthenticationFailure,
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String clientId;
  final String hmacSecretKey;
  final http.Client _httpClient;
  final Random _random = Random.secure();
  ValueChanged<AppException>? onAuthenticationFailure;

  Uri buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedQuery = queryParameters?.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
    return Uri.parse('$baseUrl$path').replace(queryParameters: normalizedQuery);
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? token,
  }) async {
    final uri = buildUri(path, queryParameters);
    final headers = _headers(
      payload: _normalizeQuery(queryParameters),
      token: token,
    );

    try {
      final response = await _httpClient.get(uri, headers: headers);
      return _handleResponse(response, authenticated: _hasToken(token));
    } on http.ClientException catch (e) {
      throw AppException('Network error: ${e.message}');
    }
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final encodedBody = jsonEncode(body);
    final headers = _headers(payload: encodedBody, token: token)
      ..['Content-Type'] = 'application/json';

    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: encodedBody,
      );
      return _handleResponse(response, authenticated: _hasToken(token));
    } on http.ClientException catch (e) {
      throw AppException('Network error: ${e.message}');
    }
  }

  Future<dynamic> uploadFile(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? token,
    Map<String, String>? fields,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.headers.addAll(_headers(payload: '', token: token));
    if (fields != null) {
      request.fields.addAll(fields);
    }
    request.files.add(
      http.MultipartFile.fromBytes(fieldName, bytes, filename: filename),
    );

    try {
      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response, authenticated: _hasToken(token));
    } on http.ClientException catch (e) {
      throw AppException('Network error: ${e.message}');
    }
  }

  Map<String, String> _headers({required String payload, String? token}) {
    if (hmacSecretKey.trim().isEmpty || clientId.trim().isEmpty) {
      throw const AppException(
        'Merchant API signing is not configured. Set MERCHANT_HMAC_SECRET_KEY and MERCHANT_CLIENT_ID.',
      );
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = _generateNonce();
    final data = '$clientId-$timestamp-$nonce-$payload';
    final signature = _generateSignature(data);
    final headers = <String, String>{
      'x-client-id': clientId,
      'x-timestamp': timestamp,
      'x-nonce': nonce,
      'x-signature': signature,
    };

    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String _generateSignature(String data) {
    final key = utf8.encode(hmacSecretKey);
    final bytes = utf8.encode(data);
    final digest = Hmac(sha256, key).convert(bytes);
    return base64Encode(digest.bytes);
  }

  String _generateNonce([int length = 16]) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _normalizeQuery(Map<String, dynamic>? parameters) {
    if (parameters == null || parameters.isEmpty) return '';
    final keys = parameters.keys.toList()..sort();
    return keys
        .map((key) => '$key=${parameters[key]?.toString() ?? ''}')
        .join('&');
  }

  dynamic _handleResponse(
    http.Response response, {
    required bool authenticated,
  }) {
    if (kDebugMode) {
      debugPrint('${response.request?.method} ${response.request?.url}');
      debugPrint('Status: ${response.statusCode}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    }

    var errorMessage = 'Request failed';
    String? errorCode;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          errorMessage =
              decoded['error']?.toString() ??
              decoded['message']?.toString() ??
              errorMessage;
          errorCode = decoded['code']?.toString();
        } else {
          errorMessage = response.body;
        }
      } catch (_) {
        errorMessage = response.body;
      }
    }

    final exception = AppException(
      errorMessage,
      statusCode: response.statusCode,
      code: errorCode,
    );
    if (authenticated &&
        (response.statusCode == 401 ||
            errorCode == 'MERCHANT_USER_INACTIVE' ||
            errorCode == 'MERCHANT_REAUTHENTICATION_REQUIRED')) {
      onAuthenticationFailure?.call(exception);
    }
    throw exception;
  }

  bool _hasToken(String? token) => token != null && token.trim().isNotEmpty;
}
