// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'merchant_local_notification_payload.dart';
import 'merchant_navigation_intent.dart';

Future<bool> showMerchantWebLocalNotification(
  MerchantLocalNotificationPayload payload,
) async {
  if (!html.Notification.supported) return false;

  var permission = html.Notification.permission;
  if (permission != 'granted') {
    permission = await html.Notification.requestPermission();
  }
  if (permission != 'granted') return false;

  final webNotification = html.Notification(
    payload.title,
    body: payload.body,
    icon: '/icons/Icon-192.png',
    tag: payload.notificationId.isEmpty
        ? payload.orderId
        : payload.notificationId,
  );

  webNotification.onClick.listen((_) {
    webNotification.close();
    MerchantNavigationIntent.notifyNotificationsChanged();
    if (payload.orderId.isNotEmpty) {
      MerchantNavigationIntent.openOrder(
        orderId: payload.orderId,
        notificationId: payload.notificationId,
      );
      return;
    }
    MerchantNavigationIntent.openOrders();
  });
  return true;
}
