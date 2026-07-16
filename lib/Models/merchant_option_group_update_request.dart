class MerchantOptionGroupUpdateRequest {
  const MerchantOptionGroupUpdateRequest({
    required this.optionGroupId,
    required this.groupName,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.optionProductIds,
  });

  final String optionGroupId;
  final String groupName;
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final List<String> optionProductIds;

  Map<String, dynamic> toJson() {
    return {
      'option_group_id': optionGroupId,
      'group_name': groupName,
      'selection_type': selectionType,
      'min_select': minSelect,
      'max_select': maxSelect,
      'option_product_ids': optionProductIds,
    };
  }
}
