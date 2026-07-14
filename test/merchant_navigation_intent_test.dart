import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Common/merchant_navigation_intent.dart';

void main() {
  test('refreshOrders does not change the selected merchant tab', () {
    MerchantNavigationIntent.selectedTabIndex.value = 2;
    final previousTick = MerchantNavigationIntent.ordersRefreshTick.value;

    MerchantNavigationIntent.refreshOrders();

    expect(MerchantNavigationIntent.selectedTabIndex.value, 2);
    expect(MerchantNavigationIntent.ordersRefreshTick.value, previousTick + 1);
  });
}
