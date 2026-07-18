class MerchantUser {
  const MerchantUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    required this.authVersion,
    required this.mustChangePassword,
    required this.lastLoginAt,
    required this.permissions,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;
  final bool active;
  final int authVersion;
  final bool mustChangePassword;
  final DateTime? lastLoginAt;
  final Set<String> permissions;

  bool hasPermission(String permission) =>
      role == 'owner' || permissions.contains(permission);

  factory MerchantUser.fromJson(Map<String, dynamic> json) {
    return MerchantUser(
      id: _firstString(json, const [
        'merchant_user_id',
        'merchantUserId',
        'id',
      ]),
      username: _firstString(json, const ['username']),
      displayName: _firstString(json, const [
        'display_name',
        'displayName',
        'name',
      ]),
      role: _firstString(json, const ['role'], fallback: 'staff'),
      active: _readBool(json['active'], fallback: true),
      authVersion: _readInt(
        json['auth_version'] ?? json['authVersion'],
        fallback: 1,
      ),
      mustChangePassword: _readBool(
        json['must_change_password'] ?? json['mustChangePassword'],
      ),
      lastLoginAt: _readDateTime(json['last_login_at'] ?? json['lastLoginAt']),
      permissions: _readStringSet(json['permissions']),
    );
  }

  Map<String, dynamic> toJson() => {
    'merchant_user_id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
    'active': active,
    'auth_version': authVersion,
    'must_change_password': mustChangePassword,
    'last_login_at': lastLoginAt?.toIso8601String(),
    'permissions': permissions.toList(growable: false),
  };
}

Set<String> _readStringSet(dynamic value) {
  if (value is! List) return <String>{};
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet();
}

bool _readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

int _readInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _readDateTime(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
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
