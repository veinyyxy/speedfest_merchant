import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Models/merchant_order.dart';
import 'package:speedfest_merchant/OrderPage/merchant_order_detail_sheet.dart';

void main() {
  testWidgets('order details show grouped option quantities and prices', (
    tester,
  ) async {
    final order = MerchantOrder.fromJson({
      'order_id': 'option-details',
      'status': 'accepted',
      'fulfillment_type': 'delivery',
      'items': [
        {
          'name': 'California',
          'quantity': 1,
          'subtotal': 10.75,
          'selected_options': [
            {
              'group_name': 'Extra adding',
              'name': 'Cheese',
              'quantity': 1,
              'unit_price': 1.0,
            },
            {
              'group_name': 'Extra adding',
              'name': 'Avocado',
              'quantity': 2,
              'unit_price': 1.0,
            },
          ],
        },
      ],
      'pricing': {'subtotal': 10.75, 'total': 13.75},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MerchantOrderDetailSheet(order: order)),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('-Extra adding:'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('1x California'), findsOneWidget);
    expect(find.text(r'CAD $10.75'), findsAtLeastNWidgets(1));
    expect(find.text('-Extra adding:'), findsOneWidget);
    expect(find.text('1x Cheese'), findsOneWidget);
    expect(find.text(r'CAD $1.00'), findsOneWidget);
    expect(find.text('2x Avocado'), findsOneWidget);
    expect(find.text(r'CAD $2.00'), findsOneWidget);
    expect(find.text('Extra adding: Cheese, Avocado'), findsNothing);
  });
}
