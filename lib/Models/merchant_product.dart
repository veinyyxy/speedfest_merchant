import 'merchant_option_group.dart';

class MerchantProduct {
  const MerchantProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.optionsAffectPrice,
    required this.status,
    required this.visibleInMenu,
    required this.imageUrl,
    required this.categoryIds,
    required this.categories,
    required this.optionGroups,
    required this.isOptionProduct,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final String id;
  final String sku;
  final String name;
  final String description;
  final double basePrice;
  final bool optionsAffectPrice;
  final String status;
  final bool visibleInMenu;
  final String imageUrl;
  final List<int> categoryIds;
  final List<String> categories;
  final List<MerchantOptionGroup> optionGroups;
  final bool isOptionProduct;
  final double ratingAverage;
  final int ratingCount;

  bool get isActive => status.toLowerCase() == 'active';
  String get categoryLabel =>
      categories.isEmpty ? 'Uncategorized' : categories.join(', ');
  String get statusLabel => status.isEmpty ? 'Unknown' : _humanize(status);
  bool get hasRatings => ratingCount > 0;

  MerchantProduct withUpdatedOptionGroup(MerchantOptionGroup updatedGroup) {
    if (!optionGroups.any((group) => group.id == updatedGroup.id)) return this;

    return MerchantProduct(
      id: id,
      sku: sku,
      name: name,
      description: description,
      basePrice: basePrice,
      optionsAffectPrice: optionsAffectPrice,
      status: status,
      visibleInMenu: visibleInMenu,
      imageUrl: imageUrl,
      categoryIds: categoryIds,
      categories: categories,
      optionGroups: [
        for (final group in optionGroups)
          group.id == updatedGroup.id ? updatedGroup : group,
      ],
      isOptionProduct: isOptionProduct,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
    );
  }

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
      optionsAffectPrice: _firstBool(json, const [
        'options_affect_price',
        'optionsAffectPrice',
      ], fallback: true),
      status: _firstString(json, const ['status'], fallback: 'inactive'),
      visibleInMenu:
          json['visible_in_menu'] != false && json['visibleInMenu'] != false,
      imageUrl: _firstString(json, const ['image_url', 'imageUrl']),
      categoryIds: _readCategoryIds(json['categories']),
      categories: _readCategoryNames(json['categories']),
      optionGroups: _readOptionGroups(json['option_groups']),
      isOptionProduct:
          json['is_option_product'] == true || json['isOptionProduct'] == true,
      ratingAverage: _firstDouble(json, const [
        'rating_average',
        'ratingAverage',
        'average_rating',
        'averageRating',
      ]),
      ratingCount: _firstInt(json, const [
        'rating_count',
        'ratingCount',
        'review_count',
        'reviewCount',
      ]),
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

int _firstInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return 0;
}

bool _firstBool(
  Map<String, dynamic> json,
  List<String> keys, {
  required bool fallback,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
  }
  return fallback;
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
