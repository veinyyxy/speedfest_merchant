import 'package:shared_preferences/shared_preferences.dart';

import '../Models/merchant_notification.dart';

class MerchantNotificationAlertRegistry {
  MerchantNotificationAlertRegistry._();

  static final instance = MerchantNotificationAlertRegistry._();
  static const _prefsKey = 'merchant_notification_alerted_keys_v1';
  static const _maxKeys = 200;

  final List<String> _alertedKeys = <String>[];
  final Set<String> _reservedKeys = <String>{};
  bool _loaded = false;

  Future<bool> shouldAlertNotification(
    MerchantNotification notification,
  ) async {
    return shouldAlert(
      notificationId: notification.id,
      eventType: notification.eventType,
      orderId: notification.resolvedOrderId,
    );
  }

  Future<bool> shouldAlert({
    required String notificationId,
    required String eventType,
    required String orderId,
  }) async {
    final key = buildKey(
      notificationId: notificationId,
      eventType: eventType,
      orderId: orderId,
    );
    if (key.isEmpty) return true;
    if (_reservedKeys.contains(key)) return false;
    _reservedKeys.add(key);

    try {
      await _ensureLoaded();
      if (_alertedKeys.contains(key)) return false;

      _alertedKeys.add(key);
      _trim();
      await _save();
      return true;
    } finally {
      _reservedKeys.remove(key);
    }
  }

  Future<void> markNotificationAlerted(
    MerchantNotification notification,
  ) async {
    await markAlerted(
      notificationId: notification.id,
      eventType: notification.eventType,
      orderId: notification.resolvedOrderId,
    );
  }

  Future<void> markAlerted({
    required String notificationId,
    required String eventType,
    required String orderId,
  }) async {
    final key = buildKey(
      notificationId: notificationId,
      eventType: eventType,
      orderId: orderId,
    );
    if (key.isEmpty) return;

    await _ensureLoaded();
    if (_alertedKeys.contains(key)) return;

    _alertedKeys.add(key);
    _trim();
    await _save();
  }

  static String buildKey({
    required String notificationId,
    required String eventType,
    required String orderId,
  }) {
    final normalizedNotificationId = notificationId.trim();
    if (normalizedNotificationId.isNotEmpty) {
      return 'notification:$normalizedNotificationId';
    }

    final normalizedEventType = eventType.trim().toLowerCase();
    final normalizedOrderId = orderId.trim();
    if (normalizedEventType.isEmpty || normalizedOrderId.isEmpty) return '';
    return 'order-event:$normalizedEventType:$normalizedOrderId';
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const <String>[];
    _alertedKeys
      ..clear()
      ..addAll(stored.where((item) => item.trim().isNotEmpty));
    _trim();
    _loaded = true;
  }

  void _trim() {
    while (_alertedKeys.length > _maxKeys) {
      _alertedKeys.removeAt(0);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, List<String>.from(_alertedKeys));
  }
}
