class MerchantServiceConfig {
  const MerchantServiceConfig._();

  static const baseUrl = String.fromEnvironment(
    'MERCHANT_API_BASE_URL',
    defaultValue: 'http://192.168.100.103:3000',
  );

  static const clientId = String.fromEnvironment(
    'MERCHANT_CLIENT_ID',
    defaultValue: 'speedfeast-merchant-client',
  );

  static const hmacSecretKey = String.fromEnvironment(
    'MERCHANT_HMAC_SECRET_KEY',
    defaultValue: '',
  );

  static const merchantLoginPath = '/api/merchant/auth/login';
  static const merchantValidatePath = '/api/merchant/auth/validate';
  static const merchantLogoutPath = '/api/merchant/auth/logout';
  static const merchantOrdersPath = '/api/merchant/orders';
  static const merchantOrderDetailPath = '/api/merchant/orders/detail';
  static const merchantOrderStatusUpdatePath =
      '/api/merchant/orders/status/update';
  static const merchantOrderRefundPath = '/api/merchant/orders/refund';
  static const merchantProductsPath = '/api/merchant/products';
  static const merchantCategoriesPath = '/api/merchant/categories';
  static const merchantCategoryCreatePath = '/api/merchant/categories/create';
  static const merchantOptionGroupsPath = '/api/merchant/option-groups';
  static const merchantProductCreatePath = '/api/merchant/products/create';
  static const merchantProductUpdatePath = '/api/merchant/products/update';
  static const merchantProductStatusUpdatePath =
      '/api/merchant/products/status/update';
  static const merchantProductMenuVisibilityUpdatePath =
      '/api/merchant/products/menu-visibility/update';
  static const merchantRewardsPath = '/api/merchant/rewards';
  static const merchantRewardCreatePath = '/api/merchant/rewards/create';
  static const merchantRewardUpdatePath = '/api/merchant/rewards/update';
  static const merchantRewardStatusPath = '/api/merchant/rewards/status';
}
