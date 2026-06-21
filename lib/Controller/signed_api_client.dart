import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../Common/merchant_service_config.dart';

class AppException implements Exception {
  const AppException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

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
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String clientId;
  final String hmacSecretKey;
  final http.Client _httpClient;
  final Random _random = Random.secure();

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
      return _handleResponse(response);
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
      return _handleResponse(response);
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

  dynamic _handleResponse(http.Response response) {
    if (kDebugMode) {
      debugPrint('${response.request?.method} ${response.request?.url}');
      debugPrint('Status: ${response.statusCode}');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    }

    var errorMessage = 'Request failed';
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          errorMessage =
              decoded['error']?.toString() ??
              decoded['message']?.toString() ??
              errorMessage;
        } else {
          errorMessage = response.body;
        }
      } catch (_) {
        errorMessage = response.body;
      }
    }

    throw AppException(errorMessage, statusCode: response.statusCode);
  }
}
