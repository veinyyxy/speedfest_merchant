import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Models/merchant_option_group.dart';
import 'package:speedfest_merchant/Models/merchant_option_group_update_request.dart';
import 'package:speedfest_merchant/Models/merchant_product.dart';

void main() {
  test('option group reads its shared product usage count', () {
    final group = MerchantOptionGroup.fromJson(const {
      'option_group_id': 'group-1',
      'group_name': 'Recommended sauce',
      'selection_type': 'multiple',
      'min_select': 1,
      'max_select': 2,
      'linked_product_count': 4,
      'options': [],
    });

    expect(group.linkedProductCount, 4);
    expect(group.isRequired, isTrue);
  });

  test('option group update sends shared group metadata and product ids', () {
    const request = MerchantOptionGroupUpdateRequest(
      optionGroupId: 'group-1',
      groupName: 'Recommended sauce',
      selectionType: 'multiple',
      minSelect: 0,
      maxSelect: 2,
      optionProductIds: ['product-1', 'product-2'],
    );

    expect(request.toJson(), {
      'option_group_id': 'group-1',
      'group_name': 'Recommended sauce',
      'selection_type': 'multiple',
      'min_select': 0,
      'max_select': 2,
      'option_product_ids': ['product-1', 'product-2'],
    });
  });

  test('products replace cached references to an updated shared group', () {
    final product = MerchantProduct.fromJson(const {
      'product_id': 'parent-1',
      'name': 'Best Seller',
      'option_groups': [
        {
          'option_group_id': 'group-1',
          'group_name': 'Sauce',
          'selection_type': 'single',
          'min_select': 0,
          'max_select': 1,
          'options': [],
        },
      ],
    });
    final updatedGroup = MerchantOptionGroup.fromJson(const {
      'option_group_id': 'group-1',
      'group_name': 'Recommended sauce',
      'selection_type': 'multiple',
      'min_select': 1,
      'max_select': 2,
      'options': [],
    });

    final updatedProduct = product.withUpdatedOptionGroup(updatedGroup);

    expect(updatedProduct.optionGroups.single.name, 'Recommended sauce');
    expect(updatedProduct.optionGroups.single.selectionType, 'multiple');
  });
}
