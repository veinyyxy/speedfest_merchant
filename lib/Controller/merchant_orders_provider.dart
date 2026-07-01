import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_order.dart';
import 'signed_api_client.dart';

class MerchantOrdersProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _errorMessage;
  String? _selectedStatus;
  List<MerchantOrder> _orders = const [];

  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;
  String? get selectedStatus => _selectedStatus;
  List<MerchantOrder> get orders => _orders;

  Future<void> fetchOrders({
    required SignedApiClient apiClient,
    required String token,
    String? status,
  }) async {
    _isLoading = true;
    _selectedStatus = status;
    _errorMessage = null;
    notifyListeners();

    try {
      final query = <String, dynamic>{
        'limit': 100,
        if (status != null && status.isNotEmpty) 'status': status,
      };
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantOrdersPath,
        queryParameters: query,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawOrders = response['orders'] as List? ?? const [];
      _orders = rawOrders
          .whereType<Map>()
          .map(
            (order) => MerchantOrder.fromJson(
              order.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load orders: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<MerchantOrder?> fetchOrderDetail({
    required SignedApiClient apiClient,
    required String token,
    required String orderId,
  }) async {
    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantOrderDetailPath,
        queryParameters: {'order_id': orderId},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final order = MerchantOrder.fromJson(
        Map<String, dynamic>.from(response['order']),
      );
      _replaceOrder(order);
      return order;
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Unable to load order detail: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrderStatus({
    required SignedApiClient apiClient,
    required String token,
    required String orderId,
    required String status,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantOrderStatusUpdatePath,
        {'order_id': orderId, 'status': status},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final order = MerchantOrder.fromJson(
        Map<String, dynamic>.from(response['order']),
      );
      _replaceOrder(order);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update order: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> refundOrder({
    required SignedApiClient apiClient,
    required String token,
    required String orderId,
    double? amount,
    String? note,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{'order_id': orderId};
      if (amount != null) {
        body['amount'] = double.parse(amount.toStringAsFixed(2));
      }
      if (note != null && note.trim().isNotEmpty) {
        body['note'] = note.trim();
      }

      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantOrderRefundPath,
        body,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final order = MerchantOrder.fromJson(
        Map<String, dynamic>.from(response['order']),
      );
      _replaceOrder(order);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to refund order: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  void _replaceOrder(MerchantOrder order) {
    final nextOrders = [..._orders];
    final index = nextOrders.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      nextOrders.insert(0, order);
    } else {
      nextOrders[index] = order;
    }
    _orders = nextOrders;
    notifyListeners();
  }
}
