import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../Common/merchant_firebase_config.dart';
import '../Common/merchant_navigation_intent.dart';
import '../Common/merchant_service_config.dart';
import '../Common/merchant_web_notification_click_stub.dart'
    if (dart.library.html) '../Common/merchant_web_notification_click_web.dart';
import 'signed_api_client.dart';

@pragma('vm:entry-point')
Future<void> merchantFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    debugPrint(
      '[FCM] background message: data=${message.data}, '
      'title=${message.notification?.title}, '
      'body=${message.notification?.body}',
    );
    if (Firebase.apps.isEmpty) {
      final options = await MerchantFirebaseConfig.loadOptions();
      if (options == null) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(options: options);
      }
    }
  } catch (_) {
    // Background handlers must never crash the app isolate.
  }
}

class MerchantNotificationService {
  MerchantNotificationService._();

  static final instance = MerchantNotificationService._();

  bool _firebaseReady = false;
  bool _listenersAttached = false;
  bool _tokenRefreshAttached = false;
  SignedApiClient? _apiClient;
  String? _authToken;
  String? _lastRegisteredToken;

  Future<MerchantNotificationRegistrationResult> registerForMerchant({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    debugPrint('[FCM] registerForMerchant start');
    if (token.trim().isEmpty) {
      debugPrint('[FCM] registerForMerchant skipped: empty merchant token');
      return const MerchantNotificationRegistrationResult(
        success: false,
        message: 'Merchant session is not available.',
      );
    }
    _apiClient = apiClient;
    _authToken = token;

    final ready = await _ensureFirebaseReady();
    if (!ready) {
      debugPrint('[FCM] Firebase is not ready');
      return const MerchantNotificationRegistrationResult(
        success: false,
        message:
            'Firebase Web config is missing. Check web/firebase-config.json or MERCHANT_FIREBASE_* dart-defines.',
      );
    }
    final supported = await _isMessagingSupported();
    if (!supported) {
      debugPrint('[FCM] Firebase messaging is not supported');
      return const MerchantNotificationRegistrationResult(
        success: false,
        message:
            'Firebase messaging is not supported in this browser or origin. Use localhost or HTTPS.',
      );
    }

    final permission = await _requestPermission();
    debugPrint('[FCM] notification permission: ${permission.name}');
    if (permission == AuthorizationStatus.denied) {
      return const MerchantNotificationRegistrationResult(
        success: false,
        message: 'Browser notification permission is denied.',
      );
    }
    _attachMessageListeners();

    final fcmTokenResult = await _readFcmToken();
    if (fcmTokenResult.token == null || fcmTokenResult.token!.isEmpty) {
      debugPrint(
        '[FCM] unable to read FCM token: ${fcmTokenResult.errorMessage}',
      );
      return MerchantNotificationRegistrationResult(
        success: false,
        message:
            fcmTokenResult.errorMessage ??
            'Unable to get a Firebase messaging token.',
      );
    }
    debugPrint('[FCM] token prefix: ${_shortToken(fcmTokenResult.token!)}');
    final registered = await _registerToken(
      apiClient: apiClient,
      token: token,
      fcmToken: fcmTokenResult.token!,
    );
    if (!registered) {
      debugPrint('[FCM] server registration failed');
      return const MerchantNotificationRegistrationResult(
        success: false,
        message: 'Unable to register notification token with the server.',
      );
    }

    _attachTokenRefreshListener();
    debugPrint('[FCM] registerForMerchant success');
    return const MerchantNotificationRegistrationResult(
      success: true,
      message: 'Notifications are enabled for this browser.',
    );
  }

  Future<void> deactivateForMerchant({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    final fcmToken = _lastRegisteredToken;
    if (token.trim().isEmpty || fcmToken == null || fcmToken.isEmpty) return;

    try {
      await apiClient.post(
        MerchantServiceConfig.merchantDeviceTokenDeactivatePath,
        {'fcm_token': fcmToken, 'platform': _platformName},
        token: token,
      );
    } catch (err) {
      debugPrint('Unable to deactivate merchant FCM token: $err');
    }
  }

  Future<bool> _ensureFirebaseReady() async {
    if (_firebaseReady) return true;

    try {
      if (Firebase.apps.isEmpty) {
        final options = await MerchantFirebaseConfig.loadOptions();
        if (kIsWeb && options == null) {
          debugPrint(
            'Merchant notifications are disabled: Firebase web config was not found.',
          );
          return false;
        }
        if (options == null) {
          await Firebase.initializeApp();
        } else {
          await Firebase.initializeApp(options: options);
        }
      }
      _firebaseReady = true;
      return true;
    } catch (err) {
      debugPrint('Merchant notifications are disabled: $err');
      return false;
    }
  }

  Future<bool> _isMessagingSupported() async {
    try {
      return FirebaseMessaging.instance.isSupported();
    } catch (err) {
      debugPrint('Unable to check Firebase messaging support: $err');
      return false;
    }
  }

  Future<AuthorizationStatus> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus;
    } catch (err) {
      debugPrint('Unable to request merchant notification permission: $err');
      return AuthorizationStatus.denied;
    }
  }

  Future<_FcmTokenResult> _readFcmToken() async {
    try {
      if (kIsWeb) {
        final webVapidKey = await MerchantFirebaseConfig.loadWebVapidKey();
        if (webVapidKey.isEmpty) {
          return const _FcmTokenResult(
            errorMessage: 'MERCHANT_FIREBASE_WEB_VAPID_KEY is not configured.',
          );
        }
        final token = await FirebaseMessaging.instance.getToken(
          vapidKey: webVapidKey,
          serviceWorkerScriptPath: '/firebase-messaging-sw.js',
        );
        return _FcmTokenResult(token: token);
      }

      final token = await FirebaseMessaging.instance.getToken();
      return _FcmTokenResult(token: token);
    } catch (err) {
      debugPrint('Unable to read merchant FCM token: $err');
      return _FcmTokenResult(errorMessage: 'Unable to get FCM token: $err');
    }
  }

  Future<bool> _registerToken({
    required SignedApiClient apiClient,
    required String token,
    required String fcmToken,
  }) async {
    if (fcmToken.trim().isEmpty) return false;

    try {
      debugPrint('[FCM] registering token on server: ${_shortToken(fcmToken)}');
      await apiClient.post(MerchantServiceConfig.merchantDeviceTokenPath, {
        'fcm_token': fcmToken,
        'platform': _platformName,
        'metadata': {'app': 'speedfeast_merchant'},
      }, token: token);
      _lastRegisteredToken = fcmToken;
      debugPrint('[FCM] server token registration success');
      return true;
    } catch (err) {
      debugPrint('Unable to register merchant FCM token: $err');
      return false;
    }
  }

  void _attachMessageListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    debugPrint('[FCM] attaching message listeners');

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message);
    });
    attachMerchantWebNotificationClickListener();
  }

  void _attachTokenRefreshListener() {
    if (_tokenRefreshAttached) return;
    _tokenRefreshAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((nextToken) {
      debugPrint('[FCM] token refreshed: ${_shortToken(nextToken)}');
      final apiClient = _apiClient;
      final token = _authToken;
      if (apiClient == null || token == null || token.isEmpty) return;
      _registerToken(apiClient: apiClient, token: token, fcmToken: nextToken);
    });
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint(
      '[FCM] notification tap: data=${message.data}, '
      'title=${message.notification?.title}, '
      'body=${message.notification?.body}',
    );
    final orderId = _orderIdFromData(message.data);
    final notificationId = _readDataText(message.data, 'notification_id');

    MerchantNavigationIntent.notifyNotificationsChanged();
    if (orderId.isEmpty) {
      MerchantNavigationIntent.openOrders();
      return;
    }

    MerchantNavigationIntent.openOrder(
      orderId: orderId,
      notificationId: notificationId,
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[FCM] foreground message: data=${message.data}, '
      'title=${message.notification?.title}, '
      'body=${message.notification?.body}',
    );
    final orderId = _orderIdFromData(message.data);
    final notificationId = _readDataText(message.data, 'notification_id');

    MerchantNavigationIntent.notifyNotificationsChanged();
    MerchantNavigationIntent.showForegroundNotification(
      title:
          message.notification?.title ??
          _readDataText(message.data, 'title').ifEmpty('SpeedFeast Merchant'),
      body:
          message.notification?.body ??
          _readDataText(
            message.data,
            'body',
          ).ifEmpty('You have a new notification.'),
      orderId: orderId,
      notificationId: notificationId,
    );
    if (orderId.isNotEmpty) {
      Future<void>.delayed(Duration.zero, () {
        MerchantNavigationIntent.openOrder(
          orderId: orderId,
          notificationId: notificationId,
          markNotificationRead: false,
        );
      });
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'unknown',
    };
  }
}

String _orderIdFromData(Map<String, dynamic> data) {
  final directOrderId = _readDataText(data, 'order_id');
  if (directOrderId.isNotEmpty) return directOrderId;

  final actionPayload = _readActionPayload(data);
  return (actionPayload['order_id'] ?? actionPayload['orderId'])
          ?.toString()
          .trim() ??
      '';
}

String _readDataText(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) return '';
  return value.toString().trim();
}

String _shortToken(String token) {
  final text = token.trim();
  if (text.length <= 24) return text;
  return text.substring(0, 24);
}

Map<String, dynamic> _readActionPayload(Map<String, dynamic> data) {
  final raw = data['action_payload'] ?? data['actionPayload'];
  if (raw is Map) {
    return raw.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

extension _EmptyStringFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class MerchantNotificationRegistrationResult {
  const MerchantNotificationRegistrationResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class _FcmTokenResult {
  const _FcmTokenResult({this.token, this.errorMessage});

  final String? token;
  final String? errorMessage;
}
