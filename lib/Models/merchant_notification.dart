class MerchantNotification {
  const MerchantNotification({
    required this.id,
    required this.eventType,
    required this.orderId,
    required this.title,
    required this.body,
    required this.actionType,
    required this.actionPayload,
    required this.payload,
    required this.deliveryStatus,
    required this.isRead,
    required this.createdAtLabel,
  });

  final String id;
  final String eventType;
  final String orderId;
  final String title;
  final String body;
  final String actionType;
  final Map<String, dynamic> actionPayload;
  final Map<String, dynamic> payload;
  final String deliveryStatus;
  final bool isRead;
  final String createdAtLabel;

  String get resolvedOrderId {
    final payloadOrderId =
        actionPayload['order_id'] ?? actionPayload['orderId'] ?? orderId;
    return payloadOrderId?.toString().trim() ?? '';
  }

  bool get opensOrder =>
      actionType.trim().toLowerCase() == 'open_order' &&
      resolvedOrderId.isNotEmpty;

  MerchantNotification copyWith({bool? isRead}) {
    return MerchantNotification(
      id: id,
      eventType: eventType,
      orderId: orderId,
      title: title,
      body: body,
      actionType: actionType,
      actionPayload: actionPayload,
      payload: payload,
      deliveryStatus: deliveryStatus,
      isRead: isRead ?? this.isRead,
      createdAtLabel: createdAtLabel,
    );
  }

  factory MerchantNotification.fromJson(Map<String, dynamic> json) {
    return MerchantNotification(
      id: _firstString(json, const ['notification_id', 'notificationId', 'id']),
      eventType: _firstString(json, const ['event_type', 'eventType']),
      orderId: _firstString(json, const ['order_id', 'orderId']),
      title: _firstString(json, const ['title'], fallback: 'Notification'),
      body: _firstString(json, const ['body', 'message']),
      actionType: _firstString(json, const [
        'action_type',
        'actionType',
      ], fallback: 'open_orders'),
      actionPayload: _asMap(
        _firstValue(json, const ['action_payload', 'actionPayload']),
      ),
      payload: _asMap(_firstValue(json, const ['payload'])),
      deliveryStatus: _firstString(json, const [
        'delivery_status',
        'deliveryStatus',
        'status',
      ]),
      isRead: _firstBool(json, const ['is_read', 'isRead']),
      createdAtLabel: _formatDate(
        _firstValue(json, const ['created_at', 'createdAt']),
      ),
    );
  }
}

dynamic _firstValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  final value = _firstValue(json, keys);
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

bool _firstBool(Map<String, dynamic> json, List<String> keys) {
  final value = _firstValue(json, keys);
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == '1' || text == 'yes';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map<String, dynamic>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

String _formatDate(dynamic value) {
  if (value == null) return '';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
