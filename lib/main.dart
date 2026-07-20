import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'Controller/merchant_orders_provider.dart';
import 'Controller/merchant_dining_tables_provider.dart';
import 'Controller/merchant_notification_service.dart';
import 'Controller/merchant_notifications_provider.dart';
import 'Controller/merchant_products_provider.dart';
import 'Controller/merchant_printers_provider.dart';
import 'Controller/merchant_rewards_provider.dart';
import 'Controller/merchant_settings_provider.dart';
import 'Controller/merchant_session_provider.dart';
import 'Controller/merchant_users_provider.dart';
import 'HomePage/merchant_shell_page.dart';
import 'LoginPage/merchant_login_page.dart';
import 'LoginPage/merchant_password_change_page.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(
    merchantFirebaseMessagingBackgroundHandler,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MerchantSessionProvider()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => MerchantOrdersProvider()),
        ChangeNotifierProvider(create: (_) => MerchantDiningTablesProvider()),
        ChangeNotifierProvider(create: (_) => MerchantNotificationsProvider()),
        ChangeNotifierProvider(create: (_) => MerchantProductsProvider()),
        ChangeNotifierProvider(
          create: (_) => MerchantPrintersProvider()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => MerchantRewardsProvider()),
        ChangeNotifierProvider(create: (_) => MerchantSettingsProvider()),
        ChangeNotifierProvider(create: (_) => MerchantUsersProvider()),
      ],
      child: const MerchantApp(),
    ),
  );
}

class MerchantApp extends StatelessWidget {
  const MerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpeedFeast Merchant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MerchantSessionProvider>();
    if (session.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!session.isLoggedIn) return const MerchantLoginPage();
    if (session.merchantUser?.mustChangePassword == true) {
      return const MerchantPasswordChangePage(required: true);
    }
    return const MerchantShellPage();
  }
}
