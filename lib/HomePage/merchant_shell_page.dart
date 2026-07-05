import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_navigation_intent.dart';
import '../Controller/merchant_notification_service.dart';
import '../Controller/merchant_session_provider.dart';
import '../OrderPage/merchant_orders_page.dart';
import '../ProductPage/merchant_products_page.dart';
import '../RewardPage/merchant_rewards_page.dart';
import '../SettingsPage/merchant_settings_page.dart';

class MerchantShellPage extends StatefulWidget {
  const MerchantShellPage({super.key});

  @override
  State<MerchantShellPage> createState() => _MerchantShellPageState();
}

class _MerchantShellPageState extends State<MerchantShellPage> {
  int _selectedIndex = 0;
  late final VoidCallback _selectedTabListener;

  static const _pages = [
    MerchantOrdersPage(),
    MerchantProductsPage(),
    MerchantRewardsPage(),
    MerchantSettingsPage(),
    _AccountPage(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = MerchantNavigationIntent.selectedTabIndex.value;
    _selectedTabListener = () {
      final nextIndex = MerchantNavigationIntent.selectedTabIndex.value;
      if (!mounted || nextIndex == _selectedIndex) return;
      setState(() => _selectedIndex = nextIndex);
    };
    MerchantNavigationIntent.selectedTabIndex.addListener(_selectedTabListener);
  }

  @override
  void dispose() {
    MerchantNavigationIntent.selectedTabIndex.removeListener(
      _selectedTabListener,
    );
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    MerchantNavigationIntent.selectedTabIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                _selectTab(index);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Icon(
                  Icons.storefront_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('Orders'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.restaurant_menu_outlined),
                  selectedIcon: Icon(Icons.restaurant_menu),
                  label: Text('Products'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.card_giftcard_outlined),
                  selectedIcon: Icon(Icons.card_giftcard),
                  label: Text('Rewards'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: Text('Settings'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_circle_outlined),
                  selectedIcon: Icon(Icons.account_circle),
                  label: Text('Account'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _pages[_selectedIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          _selectTab(index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_giftcard_outlined),
            selectedIcon: Icon(Icons.card_giftcard),
            label: 'Rewards',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class _AccountPage extends StatefulWidget {
  const _AccountPage();

  @override
  State<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<_AccountPage> {
  bool _isEnablingNotifications = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MerchantSessionProvider>();
    final user = session.merchantUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.displayName.isNotEmpty == true
                        ? user!.displayName
                        : user?.username ?? 'Merchant',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Username: ${user?.username ?? ''}'),
                  const SizedBox(height: 4),
                  Text('Role: ${user?.role ?? ''}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isEnablingNotifications ? null : _enableNotifications,
            icon: _isEnablingNotifications
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: Text(
              _isEnablingNotifications
                  ? 'Enabling notifications'
                  : 'Enable notifications',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => context.read<MerchantSessionProvider>().logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableNotifications() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) {
      _showNotificationMessage(
        'Merchant session is not available. Please login again.',
        success: false,
      );
      return;
    }

    setState(() => _isEnablingNotifications = true);
    _showNotificationMessage('Enabling notifications...');

    MerchantNotificationRegistrationResult result;
    try {
      result = await MerchantNotificationService.instance
          .registerForMerchant(apiClient: session.apiClient, token: token)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => const MerchantNotificationRegistrationResult(
              success: false,
              message:
                  'Notification setup timed out. Check browser permission, VAPID key, and service worker.',
            ),
          );
    } catch (err) {
      result = MerchantNotificationRegistrationResult(
        success: false,
        message: 'Notification setup failed: $err',
      );
    } finally {
      if (mounted) {
        setState(() => _isEnablingNotifications = false);
      }
    }
    if (!mounted) return;

    _showNotificationMessage(result.message, success: result.success);
  }

  void _showNotificationMessage(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? null : Colors.red.shade700,
      ),
    );
  }
}
