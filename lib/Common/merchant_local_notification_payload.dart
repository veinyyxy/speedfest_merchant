import '../Models/merchant_notification.dart';

class MerchantLocalNotificationPayload {
  const MerchantLocalNotificationPayload({
    required this.notificationId,
    required this.eventType,
    required this.orderId,
    required this.title,
    required this.body,
  });

  factory MerchantLocalNotificationPayload.fromNotification(
    MerchantNotification notification,
  ) {
    return MerchantLocalNotificationPayload(
      notificationId: notification.id,
      eventType: notification.eventType,
      orderId: notification.resolvedOrderId,
      title: notification.title,
      body: notification.body,
    );
  }

  final String notificationId;
  final String eventType;
  final String orderId;
  final String title;
  final String body;
}
