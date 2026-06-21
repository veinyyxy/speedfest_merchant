import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:speedfest_merchant/Controller/merchant_orders_provider.dart';
import 'package:speedfest_merchant/Controller/merchant_products_provider.dart';
import 'package:speedfest_merchant/Controller/merchant_session_provider.dart';
import 'package:speedfest_merchant/main.dart';

void main() {
  testWidgets('merchant app smoke test', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => MerchantSessionProvider()..initialize(),
          ),
          ChangeNotifierProvider(create: (_) => MerchantOrdersProvider()),
          ChangeNotifierProvider(create: (_) => MerchantProductsProvider()),
        ],
        child: const MerchantApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SpeedFeast Merchant'), findsOneWidget);
  });
}
