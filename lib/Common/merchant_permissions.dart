class MerchantPermissions {
  const MerchantPermissions._();

  static const ordersView = 'orders.view';
  static const ordersStatusUpdate = 'orders.status.update';
  static const ordersPaymentCollect = 'orders.payment.collect';
  static const ordersPaymentSync = 'orders.payment.sync';
  static const ordersRefund = 'orders.refund';
  static const ordersPrint = 'orders.print';
  static const productsView = 'products.view';
  static const productsManage = 'products.manage';
  static const productsAvailabilityManage = 'products.availability.manage';
  static const rewardsView = 'rewards.view';
  static const rewardsManage = 'rewards.manage';
  static const settingsStoreManage = 'settings.store.manage';
  static const settingsPricingManage = 'settings.pricing.manage';
  static const settingsOperationsManage = 'settings.operations.manage';
  static const settingsAutomationManage = 'settings.automation.manage';
  static const printersManage = 'printers.manage';
  static const usersView = 'users.view';
  static const usersManage = 'users.manage';

  static const settingsArea = {
    settingsStoreManage,
    settingsPricingManage,
    settingsOperationsManage,
    settingsAutomationManage,
    printersManage,
    usersView,
  };
}
