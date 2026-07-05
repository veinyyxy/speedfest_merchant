import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MerchantFirebaseConfig {
  const MerchantFirebaseConfig._();

  static const apiKey = String.fromEnvironment('MERCHANT_FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('MERCHANT_FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment(
    'MERCHANT_FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment(
    'MERCHANT_FIREBASE_PROJECT_ID',
  );
  static const authDomain = String.fromEnvironment(
    'MERCHANT_FIREBASE_AUTH_DOMAIN',
  );
  static const storageBucket = String.fromEnvironment(
    'MERCHANT_FIREBASE_STORAGE_BUCKET',
  );
  static const measurementId = String.fromEnvironment(
    'MERCHANT_FIREBASE_MEASUREMENT_ID',
  );
  static const iosBundleId = String.fromEnvironment(
    'MERCHANT_FIREBASE_IOS_BUNDLE_ID',
  );
  static const webVapidKey = String.fromEnvironment(
    'MERCHANT_FIREBASE_WEB_VAPID_KEY',
  );
  static const webConfigPath = String.fromEnvironment(
    'MERCHANT_FIREBASE_WEB_CONFIG_PATH',
    defaultValue: 'firebase-config.json',
  );

  static FirebaseOptions? _cachedOptions;
  static Map<String, dynamic>? _cachedWebConfig;
  static bool _webConfigLoadAttempted = false;

  static bool get hasExplicitOptions =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static Future<FirebaseOptions?> loadOptions() async {
    if (_cachedOptions != null) return _cachedOptions;

    final explicitOptions = _optionsFromValues(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain,
      storageBucket: storageBucket,
      measurementId: measurementId,
      iosBundleId: iosBundleId,
    );
    if (explicitOptions != null) {
      _cachedOptions = explicitOptions;
      return _cachedOptions;
    }

    if (!kIsWeb) return null;

    final decoded = await _loadWebConfig();
    if (decoded == null) return null;
    _cachedOptions = _optionsFromValues(
      apiKey: decoded['apiKey']?.toString() ?? '',
      appId: decoded['appId']?.toString() ?? '',
      messagingSenderId: decoded['messagingSenderId']?.toString() ?? '',
      projectId: decoded['projectId']?.toString() ?? '',
      authDomain: decoded['authDomain']?.toString() ?? '',
      storageBucket: decoded['storageBucket']?.toString() ?? '',
      measurementId: decoded['measurementId']?.toString() ?? '',
    );
    return _cachedOptions;
  }

  static Future<String> loadWebVapidKey() async {
    if (webVapidKey.isNotEmpty) return webVapidKey;
    if (!kIsWeb) return '';

    final decoded = await _loadWebConfig();
    if (decoded == null) return '';
    return (decoded['webVapidKey'] ??
            decoded['vapidKey'] ??
            decoded['merchant_firebase_web_vapid_key'] ??
            decoded['MERCHANT_FIREBASE_WEB_VAPID_KEY'] ??
            '')
        .toString();
  }

  static Future<Map<String, dynamic>?> _loadWebConfig() async {
    if (_webConfigLoadAttempted) return _cachedWebConfig;
    _webConfigLoadAttempted = true;

    try {
      final response = await http.get(Uri.base.resolve(webConfigPath));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Firebase web config was not loaded: HTTP ${response.statusCode}.',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      _cachedWebConfig = decoded;
      return _cachedWebConfig;
    } catch (err) {
      debugPrint('Firebase web config was not loaded: $err');
      return null;
    }
  }

  static FirebaseOptions? _optionsFromValues({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String authDomain = '',
    String storageBucket = '',
    String measurementId = '',
    String iosBundleId = '',
  }) {
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
      iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
    );
  }
}
