import 'merchant_option_group.dart';

class MerchantProduct {
  const MerchantProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.status,
    required this.visibleInMenu,
    required this.imageUrl,
    required this.categoryIds,
    required this.categories,
    required this.optionGroups,
    required this.isOptionProduct,
  });

  final String id;
  final String sku;
  final String name;
  final String description;
  final double basePrice;
  final String status;
  final bool visibleInMenu;
  final String imageUrl;
  final List<int> categoryIds;
  final List<String> categories;
  final List<MerchantOptionGroup> optionGroups;
  final bool isOptionProduct;

  bool get isActive => status.toLowerCase() == 'active';
  String get categoryLabel =>
      categories.isEmpty ? 'Uncategorized' : categories.join(', ');
  String get statusLabel => status.isEmpty ? 'Unknown' : _humanize(status);

  factory MerchantProduct.fromJson(Map<String, dynamic> json) {
    return MerchantProduct(
      id: _firstString(json, const ['product_id', 'productId', 'id']),
      sku: _firstString(json, const ['sku']),
      name: _firstString(json, const [
        'name',
        'product_name',
        'productName',
      ], fallback: 'Item'),
      description: _firstString(json, const ['description']),
      basePrice: _firstDouble(json, const ['base_price', 'basePrice', 'price']),
      status: _firstString(json, const ['status'], fallback: 'inactive'),
      visibleInMenu:
          json['visible_in_menu'] != false && json['visibleInMenu'] != false,
      imageUrl: _firstString(json, const ['image_url', 'imageUrl']),
      categoryIds: _readCategoryIds(json['categories']),
      categories: _readCategoryNames(json['categories']),
      optionGroups: _readOptionGroups(json['option_groups']),
      isOptionProduct:
          json['is_option_product'] == true || json['isOptionProduct'] == true,
    );
  }
}

List<int> _readCategoryIds(dynamic value) {
  if (value is! List) return const [];
  final ids = <int>[];
  for (final item in value) {
    if (item is! Map) continue;
    final rawId = item['category_id'] ?? item['categoryId'] ?? item['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id != null && id > 0 && !ids.contains(id)) {
      ids.add(id);
    }
  }
  return ids;
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

List<String> _readCategoryNames(dynamic value) {
  if (value is! List) return const [];
  final names = <String>[];
  for (final item in value) {
    if (item is Map) {
      final name = item['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) names.add(name);
    } else {
      final name = item.toString().trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names;
}

List<MerchantOptionGroup> _readOptionGroups(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (group) => MerchantOptionGroup.fromJson(
          group.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      )
      .where((group) => group.id.isNotEmpty)
      .toList(growable: false);
}

String _humanize(String value) {
  return value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) {
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}
