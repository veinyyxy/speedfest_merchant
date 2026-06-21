class MerchantProductCreateRequest {
  const MerchantProductCreateRequest({
    this.productId = '',
    required this.sku,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.status,
    required this.visibleInMenu,
    required this.categoryIds,
    required this.imageUrl,
    required this.optionGroups,
  });

  final String productId;
  final String sku;
  final String name;
  final String description;
  final double basePrice;
  final String status;
  final bool visibleInMenu;
  final List<int> categoryIds;
  final String imageUrl;
  final List<MerchantOptionGroupDraft> optionGroups;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'sku': sku,
      'name': name,
      'description': description,
      'base_price': basePrice,
      'status': status,
      'visible_in_menu': visibleInMenu,
      'category_ids': categoryIds,
      'image_url': imageUrl,
      'option_groups': optionGroups.map((group) => group.toJson()).toList(),
    };
    if (productId.isNotEmpty) {
      json['product_id'] = productId;
    }
    return json;
  }
}

class MerchantOptionGroupDraft {
  const MerchantOptionGroupDraft({
    required this.optionGroupId,
    required this.groupName,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.sortOrder,
    required this.options,
  });

  final String optionGroupId;
  final String groupName;
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  final List<MerchantOptionDraft> options;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'group_name': groupName,
      'selection_type': selectionType,
      'min_select': minSelect,
      'max_select': maxSelect,
      'sort_order': sortOrder,
      'options': options.map((option) => option.toJson()).toList(),
    };
    if (optionGroupId.isNotEmpty) {
      json['option_group_id'] = optionGroupId;
    }
    return json;
  }
}

class MerchantOptionDraft {
  const MerchantOptionDraft({
    required this.productId,
    required this.sku,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.status,
    required this.visibleInMenu,
    required this.imageUrl,
    required this.sortOrder,
    required this.childGroups,
  });

  final String productId;
  final String sku;
  final String name;
  final String description;
  final double basePrice;
  final String status;
  final bool visibleInMenu;
  final String imageUrl;
  final int sortOrder;
  final List<MerchantOptionGroupDraft> childGroups;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'sku': sku,
      'name': name,
      'description': description,
      'base_price': basePrice,
      'status': status,
      'visible_in_menu': visibleInMenu,
      'image_url': imageUrl,
      'sort_order': sortOrder,
      'child_groups': childGroups.map((group) => group.toJson()).toList(),
    };
    if (productId.isNotEmpty) {
      json['product_id'] = productId;
    }
    return json;
  }
}
