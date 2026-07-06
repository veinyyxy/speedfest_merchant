import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_notification.dart';
import 'signed_api_client.dart';

class MerchantNotificationsProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;
  int _unreadCount = 0;
  List<MerchantNotification> _notifications = const [];

  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;
  int get unreadCount => _unreadCount;
  List<MerchantNotification> get notifications => _notifications;

  Future<void> fetchNotifications({
    required SignedApiClient apiClient,
    required String token,
    bool unreadOnly = false,
    int limit = 30,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantNotificationsPath,
        queryParameters: {'limit': limit, if (unreadOnly) 'unread_only': true},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawNotifications = response['notifications'] as List? ?? const [];
      _notifications = rawNotifications
          .whereType<Map>()
          .map(
            (item) => MerchantNotification.fromJson(
              item.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
      _unreadCount = _notifications.where((item) => !item.isRead).length;
      await fetchUnreadCount(apiClient: apiClient, token: token);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load notifications: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUnreadCount({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantNotificationsUnreadCountPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _unreadCount = _readInt(response, const ['unread_count', 'unreadCount']);
      notifyListeners();
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Unable to load notification count: $e';
      notifyListeners();
    }
  }

  Future<bool> markRead({
    required SignedApiClient apiClient,
    required String token,
    required String notificationId,
  }) async {
    if (notificationId.trim().isEmpty) return false;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await apiClient.post(
        MerchantServiceConfig.merchantNotificationReadPath(notificationId),
        <String, dynamic>{},
        token: token,
      );
      _replaceReadState(notificationId, isRead: true);
      await fetchUnreadCount(apiClient: apiClient, token: token);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to mark notification read: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> markAllRead({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await apiClient.post(
        MerchantServiceConfig.merchantNotificationsReadAllPath,
        <String, dynamic>{},
        token: token,
      );
      _notifications = _notifications
          .map((item) => item.copyWith(isRead: true))
          .toList(growable: false);
      _unreadCount = 0;
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to mark notifications read: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> sendTestNotification({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await apiClient.post(
        MerchantServiceConfig.merchantNotificationsTestPath,
        <String, dynamic>{},
        token: token,
      );
      await fetchNotifications(apiClient: apiClient, token: token);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to send test notification: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  void _replaceReadState(String notificationId, {required bool isRead}) {
    _notifications = _notifications
        .map(
          (item) =>
              item.id == notificationId ? item.copyWith(isRead: isRead) : item,
        )
        .toList(growable: false);
  }
}

int _readInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return 0;
}
