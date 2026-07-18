class MerchantManagedUser {
  const MerchantManagedUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    required this.mustChangePassword,
    required this.lastLoginAt,
    required this.createdAt,
    required this.permissions,
    required this.permissionOverrides,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;
  final bool active;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final Set<String> permissions;
  final Map<String, String> permissionOverrides;

  bool get isOwner => role == 'owner';
  String get resolvedName => displayName.isEmpty ? username : displayName;

  factory MerchantManagedUser.fromJson(Map<String, dynamic> json) {
    final rawOverrides = json['permission_overrides'];
    final overrides = <String, String>{};
    if (rawOverrides is List) {
      for (final item in rawOverrides.whereType<Map>()) {
        final key = item['permission_key']?.toString().trim() ?? '';
        final effect = item['effect']?.toString().trim() ?? '';
        if (key.isNotEmpty && (effect == 'allow' || effect == 'deny')) {
          overrides[key] = effect;
        }
      }
    }

    return MerchantManagedUser(
      id: _text(json['merchant_user_id'] ?? json['merchantUserId']),
      username: _text(json['username']),
      displayName: _text(json['display_name'] ?? json['displayName']),
      role: _text(json['role']).toLowerCase(),
      active: _bool(json['active'], fallback: true),
      mustChangePassword: _bool(
        json['must_change_password'] ?? json['mustChangePassword'],
      ),
      lastLoginAt: _date(json['last_login_at'] ?? json['lastLoginAt']),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
      permissions: _stringSet(json['permissions']),
      permissionOverrides: overrides,
    );
  }
}

class MerchantPermissionDefinition {
  const MerchantPermissionDefinition({
    required this.key,
    required this.module,
    required this.displayName,
    required this.description,
    required this.sortOrder,
  });

  final String key;
  final String module;
  final String displayName;
  final String description;
  final int sortOrder;

  factory MerchantPermissionDefinition.fromJson(Map<String, dynamic> json) {
    return MerchantPermissionDefinition(
      key: _text(json['permission_key'] ?? json['permissionKey']),
      module: _text(json['module']),
      displayName: _text(json['display_name'] ?? json['displayName']),
      description: _text(json['description']),
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';

bool _bool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

DateTime? _date(dynamic value) {
  final text = _text(value);
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
}

Set<String> _stringSet(dynamic value) {
  if (value is! List) return <String>{};
  return value.map(_text).where((item) => item.isNotEmpty).toSet();
}
