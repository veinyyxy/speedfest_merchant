// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'merchant_navigation_intent.dart';

bool _attached = false;

void attachMerchantWebNotificationClickListener() {
  if (_attached) return;
  _attached = true;

  html.window.navigator.serviceWorker?.onMessage.listen((event) {
    final envelope = _asMap(event.data);
    final type = envelope['type']?.toString().trim() ?? '';
    if (type != 'merchant_notification_click') return;

    final data = _asMap(envelope['data']);
    final orderId = _orderIdFromData(data);
    final notificationId = data['notification_id']?.toString().trim() ?? '';

    MerchantNavigationIntent.notifyNotificationsChanged();
    if (orderId.isEmpty) {
      MerchantNavigationIntent.openOrders();
      return;
    }

    MerchantNavigationIntent.openOrder(
      orderId: orderId,
      notificationId: notificationId,
    );
  });
}

String _orderIdFromData(Map<String, dynamic> data) {
  final directOrderId = data['order_id']?.toString().trim() ?? '';
  if (directOrderId.isNotEmpty) return directOrderId;

  final actionPayload = _readActionPayload(data);
  return (actionPayload['order_id'] ?? actionPayload['orderId'])
          ?.toString()
          .trim() ??
      '';
}

Map<String, dynamic> _readActionPayload(Map<String, dynamic> data) {
  final raw = data['action_payload'] ?? data['actionPayload'];
  if (raw is Map) return _asMap(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      return _asMap(decoded);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map<String, dynamic>(
    (key, value) => MapEntry(key.toString(), value),
  );
}
