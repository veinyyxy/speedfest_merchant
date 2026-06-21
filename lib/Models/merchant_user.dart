class MerchantUser {
  const MerchantUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;

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
    );
  }

  Map<String, dynamic> toJson() => {
    'merchant_user_id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
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
