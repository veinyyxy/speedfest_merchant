class MerchantOptionGroup {
  const MerchantOptionGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  final String id;
  final String name;
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final List<MerchantOptionGroupOption> options;

  bool get isRequired => minSelect > 0;
  String get selectionLabel =>
      selectionType == 'multiple' ? 'Multiple' : 'Single';
  String get summary {
    final optionText = options.isEmpty
        ? 'no options'
        : '${options.length} option${options.length == 1 ? '' : 's'}';
    return '$selectionLabel · $optionText';
  }

  factory MerchantOptionGroup.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List? ?? const [];
    return MerchantOptionGroup(
      id: _firstString(json, const ['option_group_id', 'optionGroupId', 'id']),
      name: _firstString(json, const ['group_name', 'groupName', 'title']),
      selectionType:
          _firstString(json, const ['selection_type', 'selectionType']) ==
              'multiple'
          ? 'multiple'
          : 'single',
      minSelect: _firstInt(json, const ['min_select', 'minSelect']),
      maxSelect: _firstInt(json, const [
        'max_select',
        'maxSelect',
      ], fallback: 1),
      options: rawOptions
          .whereType<Map>()
          .map(
            (option) => MerchantOptionGroupOption.fromJson(
              option.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class MerchantOptionGroupOption {
  const MerchantOptionGroupOption({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.status,
  });

  final String id;
  final String name;
  final double basePrice;
  final String status;

  factory MerchantOptionGroupOption.fromJson(Map<String, dynamic> json) {
    return MerchantOptionGroupOption(
      id: _firstString(json, const ['product_id', 'productId', 'id']),
      name: _firstString(json, const [
        'name',
        'product_name',
      ], fallback: 'Item'),
      basePrice: _firstDouble(json, const ['base_price', 'basePrice', 'price']),
      status: _firstString(json, const ['status'], fallback: 'inactive'),
    );
  }
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

int _firstInt(
  Map<String, dynamic> json,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    final parsed = int.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return fallback;
}

double _firstDouble(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return 0;
}
