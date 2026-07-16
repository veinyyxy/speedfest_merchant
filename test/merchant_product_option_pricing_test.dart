import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Models/merchant_product.dart';
import 'package:speedfest_merchant/Models/merchant_product_create_request.dart';

void main() {
  test('existing products keep option pricing enabled by default', () {
    final product = MerchantProduct.fromJson(const {
      'product_id': 'product-1',
      'name': 'Existing product',
    });

    expect(product.optionsAffectPrice, isTrue);
  });

  test('merchant product request persists included option pricing', () {
    const request = MerchantProductCreateRequest(
      sku: 'BEST-SELLER',
      name: 'Best Seller',
      description: 'Combo',
      basePrice: 20,
      optionsAffectPrice: false,
      status: 'active',
      visibleInMenu: true,
      categoryIds: [1],
      imageUrl: '',
      optionGroups: [],
    );

    expect(request.toJson()['options_affect_price'], isFalse);
  });
}
