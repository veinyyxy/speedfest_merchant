import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../Models/merchant_notification.dart';
import 'merchant_local_notification_payload.dart';
import 'merchant_navigation_intent.dart';
import 'merchant_web_local_notification_stub.dart'
    if (dart.library.html) 'merchant_web_local_notification_web.dart';

class MerchantLocalNotificationService {
  MerchantLocalNotificationService._();

  static final instance = MerchantLocalNotificationService._();
  static const _channel = MethodChannel(
    'speedfeast_merchant/local_notifications',
  );

  bool _tapListenerAttached = false;

  void attachTapListener() {
    if (_tapListenerAttached || kIsWeb) return;
    _tapListenerAttached = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    _consumeInitialNotificationTap();
  }

  Future<void> show(MerchantNotification notification) async {
    await showPayload(
      MerchantLocalNotificationPayload.fromNotification(notification),
    );
  }

  Future<void> showPayload(MerchantLocalNotificationPayload payload) async {
    if (payload.title.trim().isEmpty) return;

    if (kIsWeb) {
      await showMerchantWebLocalNotification(payload);
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<bool>('showMerchantNotification', {
        'notificationId': payload.notificationId,
        'eventType': payload.eventType,
        'orderId': payload.orderId,
        'title': payload.title,
        'body': payload.body,
        'channelId': _androidChannelId(payload.eventType),
      });
    } on MissingPluginException catch (err) {
      debugPrint('Merchant local notifications are unavailable: $err');
    } catch (err) {
      debugPrint('Unable to show merchant local notification: $err');
    }
  }

  Future<void> _consumeInitialNotificationTap() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
        'consumeInitialNotificationTap',
      );
      _handleTapPayload(raw);
    } catch (err) {
      debugPrint('Unable to read merchant local notification tap: $err');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'notificationTap') return;
    final raw = call.arguments;
    if (raw is Map) {
      _handleTapPayload(raw);
    }
  }

  void _handleTapPayload(Map<dynamic, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return;

    final orderId = raw['orderId']?.toString().trim() ?? '';
    final notificationId = raw['notificationId']?.toString().trim() ?? '';
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
}

String _androidChannelId(String eventType) {
  return eventType.trim().toLowerCase() == 'customer_cancelled_order'
      ? 'order_cancelled'
      : 'new_orders';
}
