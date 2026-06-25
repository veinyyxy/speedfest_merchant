class MerchantReward {
  const MerchantReward({
    required this.id,
    required this.title,
    required this.description,
    required this.pointsCost,
    required this.discountAmount,
    required this.expiresInDays,
    required this.active,
    required this.sortOrder,
    required this.rewardType,
    required this.currency,
    this.productId = '',
    this.productName = '',
    this.productImagePath,
    this.productBasePrice = 0,
    this.productStatus = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final int pointsCost;
  final double discountAmount;
  final int expiresInDays;
  final bool active;
  final int sortOrder;
  final String rewardType;
  final String currency;
  final String productId;
  final String productName;
  final String? productImagePath;
  final double productBasePrice;
  final String productStatus;
  final String? createdAt;
  final String? updatedAt;

  bool get isProductReward => rewardType.toLowerCase() == 'product';

  String get valueLabel => isProductReward
      ? (productName.isEmpty ? 'Free product' : 'Free product: $productName')
      : '${currency.toUpperCase()} \$${discountAmount.toStringAsFixed(2)} off';

  factory MerchantReward.fromJson(Map<String, dynamic> json) {
    return MerchantReward(
      id: _firstString(json, const ['reward_id', 'rewardId', 'id']),
      title: _firstString(json, const ['title'], fallback: 'Reward'),
      description: _firstString(json, const ['description']),
      pointsCost: _firstInt(json, const ['points_cost', 'pointsCost']),
      discountAmount: _firstDouble(json, const [
        'discount_amount',
        'discountAmount',
      ]),
      expiresInDays: _firstInt(json, const [
        'expires_in_days',
        'expiresInDays',
      ], fallback: 30),
      active: json['active'] != false,
      sortOrder: _firstInt(json, const ['sort_order', 'sortOrder']),
      rewardType: _firstString(json, const [
        'reward_type',
        'rewardType',
      ], fallback: 'discount'),
      currency: _firstString(json, const ['currency'], fallback: 'CAD'),
      productId: _firstString(json, const ['product_id', 'productId']),
      productName: _firstString(json, const ['product_name', 'productName']),
      productImagePath: _nullableString(
        json['product_image_path'] ?? json['productImagePath'],
      ),
      productBasePrice: _firstDouble(json, const [
        'product_base_price',
        'productBasePrice',
      ]),
      productStatus: _firstString(json, const [
        'product_status',
        'productStatus',
      ]),
      createdAt: _nullableString(json['created_at'] ?? json['createdAt']),
      updatedAt: _nullableString(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toSaveJson() => {
    if (id.isNotEmpty) 'reward_id': id,
    'title': title,
    'description': description,
    'points_cost': pointsCost,
    'reward_type': rewardType,
    if (productId.isNotEmpty) 'product_id': productId,
    'discount_amount': discountAmount,
    'expires_in_days': expiresInDays,
    'active': active,
    'sort_order': sortOrder,
  };
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

String? _nullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _firstInt(
  Map<String, dynamic> json,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is num) return value.toInt();
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
