import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Common/merchant_navigation_intent.dart';

void main() {
  test('refreshOrders does not change the selected merchant tab', () {
    MerchantNavigationIntent.selectedTabIndex.value = 2;
    MerchantNavigationIntent.selectedDestinationId.value =
        MerchantNavigationIntent.rewardsDestination;
    final previousTick = MerchantNavigationIntent.ordersRefreshTick.value;

    MerchantNavigationIntent.refreshOrders();

    expect(MerchantNavigationIntent.selectedTabIndex.value, 2);
    expect(
      MerchantNavigationIntent.selectedDestinationId.value,
      MerchantNavigationIntent.rewardsDestination,
    );
    expect(MerchantNavigationIntent.ordersRefreshTick.value, previousTick + 1);
  });

  test('openOrders uses the stable orders destination', () {
    MerchantNavigationIntent.selectedDestinationId.value =
        MerchantNavigationIntent.accountDestination;

    MerchantNavigationIntent.openOrders();

    expect(
      MerchantNavigationIntent.selectedDestinationId.value,
      MerchantNavigationIntent.ordersDestination,
    );
  });

  test('openOrder also navigates from any visible destination to orders', () {
    MerchantNavigationIntent.selectedDestinationId.value =
        MerchantNavigationIntent.settingsDestination;

    MerchantNavigationIntent.openOrder(orderId: 'order-id', refresh: false);

    expect(
      MerchantNavigationIntent.selectedDestinationId.value,
      MerchantNavigationIntent.ordersDestination,
    );
    expect(MerchantNavigationIntent.orderOpenIntent.value?.orderId, 'order-id');
  });
}
