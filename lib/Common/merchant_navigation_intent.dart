import 'package:flutter/foundation.dart';

class MerchantNavigationIntent {
  const MerchantNavigationIntent._();

  static const ordersDestination = 'orders';
  static const productsDestination = 'products';
  static const rewardsDestination = 'rewards';
  static const settingsDestination = 'settings';
  static const accountDestination = 'account';

  static final selectedTabIndex = ValueNotifier<int>(0);
  static final selectedDestinationId = ValueNotifier<String>(ordersDestination);
  static final ordersRefreshTick = ValueNotifier<int>(0);
  static final orderOpenIntent = ValueNotifier<MerchantOrderOpenIntent?>(null);
  static final notificationsRefreshTick = ValueNotifier<int>(0);
  static final foregroundNotification =
      ValueNotifier<MerchantForegroundNotificationIntent?>(null);

  static int _sequence = 0;

  static void openOrders({bool refresh = true}) {
    selectedTabIndex.value = 0;
    selectedDestinationId.value = ordersDestination;
    if (refresh) {
      refreshOrders();
    }
  }

  static void refreshOrders() {
    ordersRefreshTick.value += 1;
  }

  static void openOrder({
    required String orderId,
    String notificationId = '',
    bool refresh = true,
    bool markNotificationRead = true,
  }) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      openOrders(refresh: refresh);
      return;
    }

    selectedTabIndex.value = 0;
    selectedDestinationId.value = ordersDestination;
    orderOpenIntent.value = MerchantOrderOpenIntent(
      sequence: _nextSequence(),
      orderId: normalizedOrderId,
      notificationId: notificationId.trim(),
      refreshOrders: refresh,
      markNotificationRead: markNotificationRead,
    );
  }

  static void notifyNotificationsChanged() {
    notificationsRefreshTick.value += 1;
  }

  static void showForegroundNotification({
    required String title,
    required String body,
    String eventType = '',
    String orderId = '',
    String notificationId = '',
  }) {
    foregroundNotification.value = MerchantForegroundNotificationIntent(
      sequence: _nextSequence(),
      title: title.trim(),
      body: body.trim(),
      eventType: eventType.trim(),
      orderId: orderId.trim(),
      notificationId: notificationId.trim(),
    );
  }

  static int _nextSequence() {
    _sequence += 1;
    return _sequence;
  }
}

class MerchantOrderOpenIntent {
  const MerchantOrderOpenIntent({
    required this.sequence,
    required this.orderId,
    required this.notificationId,
    required this.refreshOrders,
    required this.markNotificationRead,
  });

  final int sequence;
  final String orderId;
  final String notificationId;
  final bool refreshOrders;
  final bool markNotificationRead;
}

class MerchantForegroundNotificationIntent {
  const MerchantForegroundNotificationIntent({
    required this.sequence,
    required this.title,
    required this.body,
    required this.eventType,
    required this.orderId,
    required this.notificationId,
  });

  final int sequence;
  final String title;
  final String body;
  final String eventType;
  final String orderId;
  final String notificationId;
}
