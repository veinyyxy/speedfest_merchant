import 'package:flutter/foundation.dart';

class MerchantNavigationIntent {
  const MerchantNavigationIntent._();

  static final selectedTabIndex = ValueNotifier<int>(0);
  static final ordersRefreshTick = ValueNotifier<int>(0);

  static void openOrders({bool refresh = true}) {
    selectedTabIndex.value = 0;
    if (refresh) {
      ordersRefreshTick.value += 1;
    }
  }
}
