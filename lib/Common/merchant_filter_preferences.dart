import 'package:shared_preferences/shared_preferences.dart';

class MerchantFilterPreferences {
  const MerchantFilterPreferences._();

  static const ordersDateFilter = 'merchant.orders.date_filter';
  static const ordersDateStart = 'merchant.orders.date_start';
  static const ordersDateEnd = 'merchant.orders.date_end';
  static const ordersFulfillmentFilter = 'merchant.orders.fulfillment_filter';
  static const ordersStatusFilter = 'merchant.orders.status_filter';

  static const productsStatusFilter = 'merchant.products.status_filter';
  static const productsTypeFilter = 'merchant.products.type_filter';

  static const rewardsStatusFilter = 'merchant.rewards.status_filter';

  static Future<String?> readString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> writeString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
