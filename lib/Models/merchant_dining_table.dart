class MerchantDiningTable {
  const MerchantDiningTable({
    required this.id,
    required this.storeId,
    required this.tableNumber,
    required this.tableToken,
    required this.qrPayload,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String storeId;
  final String tableNumber;
  final String tableToken;
  final String qrPayload;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get effectiveQrPayload => qrPayload.isNotEmpty
      ? qrPayload
      : 'speedfeast://dine-in/table?table_token=${Uri.encodeQueryComponent(tableToken)}';

  factory MerchantDiningTable.fromJson(Map<String, dynamic> json) {
    return MerchantDiningTable(
      id: _text(json['table_id'] ?? json['tableId']),
      storeId: _text(json['store_id'] ?? json['storeId']),
      tableNumber: _text(json['table_number'] ?? json['tableNumber']),
      tableToken: _text(json['table_token'] ?? json['tableToken']),
      qrPayload: _text(json['qr_payload'] ?? json['qrPayload']),
      isActive: _bool(json['is_active'] ?? json['isActive'], fallback: true),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
      updatedAt: _date(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';

bool _bool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  final normalized = _text(value).toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}

DateTime? _date(dynamic value) {
  final normalized = _text(value);
  return normalized.isEmpty ? null : DateTime.tryParse(normalized)?.toLocal();
}
