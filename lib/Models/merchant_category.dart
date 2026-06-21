class MerchantCategory {
  const MerchantCategory({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;

  factory MerchantCategory.fromJson(Map<String, dynamic> json) {
    return MerchantCategory(
      id: _readInt(json['category_id'] ?? json['categoryId'] ?? json['id']),
      name: json['name']?.toString().trim() ?? 'Category',
      parentId: _readNullableInt(json['parent_id'] ?? json['parentId']),
    );
  }
}

int _readInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _readNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}
