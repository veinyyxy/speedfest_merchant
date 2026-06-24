class MerchantOrder {
  const MerchantOrder({
    required this.id,
    required this.status,
    required this.fulfillmentType,
    required this.totalAmount,
    required this.currency,
    required this.itemCount,
    required this.createdAtLabel,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.paymentStatus,
    required this.shippingAddress,
    required this.tableNumber,
    required this.pickupLocation,
    required this.deliveryNote,
    required this.items,
    required this.review,
    required this.pricing,
  });

  final String id;
  final String status;
  final String fulfillmentType;
  final double totalAmount;
  final String currency;
  final int itemCount;
  final String createdAtLabel;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String paymentStatus;
  final String shippingAddress;
  final String tableNumber;
  final String pickupLocation;
  final String deliveryNote;
  final List<MerchantOrderItem> items;
  final MerchantOrderReview? review;
  final MerchantOrderPricing pricing;

  String get displayId => id.isEmpty ? 'Order' : 'Order #${_shortId(id)}';
  String get normalizedStatus => status.trim().toLowerCase();
  String get normalizedPaymentStatus => paymentStatus.trim().toLowerCase();
  String get normalizedFulfillmentType {
    final normalized = fulfillmentType.trim().toLowerCase().replaceAll(
      '-',
      '_',
    );
    if (normalized == 'take_out') return 'takeout';
    return normalized;
  }

  bool get isDelivery => normalizedFulfillmentType == 'delivery';
  bool get isTakeout => normalizedFulfillmentType == 'takeout';
  bool get isDineIn => normalizedFulfillmentType == 'dine_in';
  bool get isPendingPayment =>
      normalizedStatus == 'created' || normalizedPaymentStatus == 'pending';
  String get fulfillmentLabel => _humanize(fulfillmentType);
  String get statusLabel =>
      isPendingPayment ? 'Pending payment' : _humanize(status);
  String get displayStatusLabel => statusLabel;
  String get paymentStatusLabel => _humanize(paymentStatus);
  bool get isReviewed => review != null;
  String get reviewComment => review?.comment ?? '';

  factory MerchantOrder.fromJson(Map<String, dynamic> json) {
    final customer = _asMap(_firstValue(json, const ['customer', 'user']));
    final pricing = _asMap(_firstValue(json, const ['pricing']));
    final reviewData = _asMap(
      _firstValue(json, const ['review', 'order_review', 'orderReview']),
    );
    final items = _readList(json, const [
      'items',
      'order_items',
      'orderItems',
    ]).map(MerchantOrderItem.fromJson).toList(growable: false);

    return MerchantOrder(
      id: _firstString(json, const ['order_id', 'orderId', 'id']),
      status: _firstString(json, const [
        'order_status',
        'orderStatus',
        'status',
      ], fallback: 'created'),
      fulfillmentType: _firstString(json, const [
        'fulfillment_type',
        'fulfillmentType',
      ]),
      totalAmount: _firstDouble(json, const [
        'total_amount',
        'totalAmount',
        'total',
      ]),
      currency: _firstString(json, const ['currency'], fallback: 'CAD'),
      itemCount: _firstInt(json, const [
        'item_count',
        'itemCount',
      ], fallback: items.fold<int>(0, (sum, item) => sum + item.quantity)),
      createdAtLabel: _formatDate(
        _firstValue(json, const ['created_at', 'createdAt', 'date']),
      ),
      customerName: _firstString(customer, const [
        'username',
        'display_name',
        'displayName',
        'name',
      ]),
      customerPhone: _firstString(customer, const [
        'cell_phone',
        'cellPhone',
        'phone',
      ]),
      customerEmail: _firstString(customer, const ['email']),
      paymentStatus: _firstString(json, const [
        'payment_status',
        'paymentStatus',
      ]),
      shippingAddress: _formatAddress(
        _firstValue(json, const [
          'shipping_address',
          'shippingAddress',
          'address',
        ]),
      ),
      tableNumber: _firstString(json, const ['table_number', 'tableNumber']),
      pickupLocation: _firstString(json, const [
        'pickup_location',
        'pickupLocation',
      ]),
      deliveryNote: _firstString(json, const ['delivery_note', 'deliveryNote']),
      items: items,
      review: reviewData.isEmpty
          ? null
          : MerchantOrderReview.fromJson(reviewData),
      pricing: MerchantOrderPricing.fromJson(pricing),
    );
  }
}

class MerchantOrderItem {
  const MerchantOrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.options,
    required this.specialInstructions,
    this.reviewRating = 0,
  });

  final String name;
  final int quantity;
  final double price;
  final List<MerchantOrderItemOption> options;
  final String specialInstructions;
  final int reviewRating;

  String get optionsLabel {
    if (options.isEmpty) return '';
    final grouped = <String, List<String>>{};
    for (final option in options) {
      if (option.name.isEmpty) continue;
      grouped.putIfAbsent(option.groupName, () => <String>[]).add(option.name);
    }

    return grouped.entries
        .map((entry) {
          final names = entry.value.join(', ');
          return entry.key.isEmpty ? names : '${entry.key}: $names';
        })
        .join(' · ');
  }

  factory MerchantOrderItem.fromJson(Map<String, dynamic> json) {
    return MerchantOrderItem(
      name: _firstString(json, const [
        'product_name',
        'productName',
        'name',
        'title',
      ], fallback: 'Item'),
      quantity: _firstInt(json, const ['quantity', 'qty'], fallback: 1),
      price: _firstDouble(json, const ['subtotal', 'price', 'unit_price']),
      options: _readList(json, const [
        'selected_options',
        'selectedOptions',
        'options',
      ]).map(MerchantOrderItemOption.fromJson).toList(growable: false),
      specialInstructions: _firstString(json, const [
        'special_instructions',
        'specialInstructions',
      ]),
      reviewRating: _firstInt(json, const [
        'review_rating',
        'reviewRating',
        'rating',
      ]),
    );
  }
}

class MerchantOrderReview {
  const MerchantOrderReview({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.comment,
    required this.createdAtLabel,
    required this.updatedAtLabel,
    required this.items,
  });

  final String id;
  final String orderId;
  final String userId;
  final String comment;
  final String createdAtLabel;
  final String updatedAtLabel;
  final List<MerchantOrderReviewItem> items;

  bool get hasComment => comment.trim().isNotEmpty;
  bool get hasItemRatings => items.any((item) => item.rating > 0);

  factory MerchantOrderReview.fromJson(Map<String, dynamic> json) {
    return MerchantOrderReview(
      id: _firstString(json, const ['review_id', 'reviewId', 'id']),
      orderId: _firstString(json, const ['order_id', 'orderId']),
      userId: _firstString(json, const ['user_id', 'userId']),
      comment: _firstString(json, const [
        'comment',
        'message',
        'review_comment',
        'reviewComment',
      ]),
      createdAtLabel: _formatDate(
        _firstValue(json, const ['created_at', 'createdAt']),
      ),
      updatedAtLabel: _formatDate(
        _firstValue(json, const ['updated_at', 'updatedAt']),
      ),
      items: _readList(json, const [
        'items',
        'item_reviews',
        'itemReviews',
      ]).map(MerchantOrderReviewItem.fromJson).toList(growable: false),
    );
  }
}

class MerchantOrderReviewItem {
  const MerchantOrderReviewItem({
    required this.id,
    required this.orderItemId,
    required this.productId,
    required this.rating,
  });

  final String id;
  final String orderItemId;
  final String productId;
  final int rating;

  factory MerchantOrderReviewItem.fromJson(Map<String, dynamic> json) {
    return MerchantOrderReviewItem(
      id: _firstString(json, const ['review_id', 'reviewId', 'id']),
      orderItemId: _firstString(json, const ['order_item_id', 'orderItemId']),
      productId: _firstString(json, const ['product_id', 'productId']),
      rating: _firstInt(json, const ['rating', 'stars']),
    );
  }
}

class MerchantOrderItemOption {
  const MerchantOrderItemOption({required this.name, required this.groupName});

  final String name;
  final String groupName;

  factory MerchantOrderItemOption.fromJson(Map<String, dynamic> json) {
    return MerchantOrderItemOption(
      name: _firstString(json, const [
        'option_name',
        'optionName',
        'name',
        'title',
      ]),
      groupName: _firstString(json, const [
        'group_name',
        'groupName',
        'option_group_name',
      ]),
    );
  }
}

class MerchantOrderPricing {
  const MerchantOrderPricing({
    required this.subtotal,
    required this.deliveryFee,
    required this.deliveryServiceFee,
    required this.taxes,
    required this.tipAmount,
    required this.total,
  });

  final double subtotal;
  final double deliveryFee;
  final double deliveryServiceFee;
  final double taxes;
  final double tipAmount;
  final double total;

  factory MerchantOrderPricing.fromJson(Map<String, dynamic> json) {
    return MerchantOrderPricing(
      subtotal: _firstDouble(json, const ['subtotal']),
      deliveryFee: _firstDouble(json, const ['delivery_fee', 'deliveryFee']),
      deliveryServiceFee: _firstDouble(json, const [
        'delivery_service_fee',
        'deliveryServiceFee',
      ]),
      taxes: _firstDouble(json, const ['taxes']),
      tipAmount: _firstDouble(json, const ['tip_amount', 'tipAmount']),
      total: _firstDouble(json, const ['total']),
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

double _firstDouble(Map<String, dynamic> json, List<String> keys) {
  final value = _firstValue(json, keys);
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _firstInt(
  Map<String, dynamic> json,
  List<String> keys, {
  int fallback = 0,
}) {
  final value = _firstValue(json, keys);
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map<String, dynamic>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

List<Map<String, dynamic>> _readList(
  Map<String, dynamic> json,
  List<String> keys,
) {
  final value = _firstValue(json, keys);
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map(
        (item) => item.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      )
      .toList(growable: false);
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

String _formatAddress(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  final data = _asMap(value);
  if (data.isEmpty) return value.toString();

  final parts =
      [
            data['receiver_name'] ?? data['receiverName'],
            data['street'],
            data['city'],
            data['province'],
            data['postal_code'] ?? data['postalCode'],
            data['country'],
          ]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .map((part) => part.toString().trim())
          .toList();
  return parts.join(', ');
}

String _humanize(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) return '';
  return cleaned
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) {
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String _shortId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 8) return trimmed;
  return trimmed.substring(0, 8);
}
