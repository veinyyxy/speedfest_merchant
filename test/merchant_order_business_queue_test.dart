import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Models/merchant_order.dart';
import 'package:speedfest_merchant/OrderPage/merchant_orders_page.dart';

void main() {
  test('delivery queue counts use the existing business status mapping', () {
    final counts = countMerchantBusinessQueues(
      [
        _order('paid', 'delivery'),
        _order('accepted', 'delivery'),
        _order('preparing', 'delivery'),
        _order('ready', 'delivery'),
        _order('on_the_way', 'delivery'),
        _order('delivered', 'delivery'),
        _order('cancelled', 'delivery'),
        _order('paid', 'takeout'),
      ],
      fulfillmentType: 'delivery',
      queues: const ['new_order', 'ready', 'on_the_way', 'delivered'],
    );

    expect(counts, {
      'new_order': 3,
      'ready': 1,
      'on_the_way': 1,
      'delivered': 1,
    });
  });

  test('non-delivery queue counts include in-store collection orders', () {
    final counts = countMerchantBusinessQueues(
      [
        _order(
          'created',
          'takeout',
          paymentChannel: 'in_store',
          paymentStatus: 'awaiting_collection',
        ),
        _order(
          'ready',
          'takeout',
          paymentChannel: 'in_store',
          paymentStatus: 'awaiting_collection',
        ),
        _order(
          'completed',
          'takeout',
          paymentChannel: 'in_store',
          paymentStatus: 'awaiting_collection',
        ),
        _order('paid', 'takeout'),
        _order('ready', 'dine_in'),
      ],
      fulfillmentType: 'takeout',
      queues: const ['new_order', 'ready', 'awaiting_collection', 'completed'],
    );

    expect(counts, {
      'new_order': 2,
      'ready': 1,
      'awaiting_collection': 3,
      'completed': 1,
    });
  });

  test('an unknown queue never matches an order', () {
    expect(
      merchantOrderMatchesBusinessQueue(
        _order('paid', 'delivery'),
        fulfillmentType: 'delivery',
        queue: 'unknown',
      ),
      isFalse,
    );
  });
}

MerchantOrder _order(
  String status,
  String fulfillmentType, {
  String paymentChannel = 'online',
  String paymentStatus = 'paid',
}) {
  return MerchantOrder.fromJson({
    'order_id': '$fulfillmentType-$status',
    'status': status,
    'fulfillment_type': fulfillmentType,
    'payment_channel': paymentChannel,
    'payment_status': paymentStatus,
    'items': const [],
    'pricing': const {'total': 0},
  });
}
