import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_navigation_intent.dart';
import '../Controller/merchant_notification_service.dart';
import '../Controller/merchant_notifications_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_notification.dart';
import '../OrderPage/merchant_orders_page.dart';
import '../ProductPage/merchant_products_page.dart';
import '../RewardPage/merchant_rewards_page.dart';
import '../SettingsPage/merchant_settings_page.dart';

typedef _OpenNotificationCallback =
    Future<void> Function(MerchantNotification notification);

class MerchantShellPage extends StatefulWidget {
  const MerchantShellPage({super.key});

  @override
  State<MerchantShellPage> createState() => _MerchantShellPageState();
}

class _MerchantShellPageState extends State<MerchantShellPage> {
  int _selectedIndex = 0;
  late final VoidCallback _selectedTabListener;
  late final VoidCallback _notificationsRefreshListener;
  late final VoidCallback _foregroundNotificationListener;
  int _lastForegroundNotificationSequence = 0;

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
    _notificationsRefreshListener = () {
      if (!mounted) return;
      _refreshNotificationCount();
    };
    MerchantNavigationIntent.notificationsRefreshTick.addListener(
      _notificationsRefreshListener,
    );
    _foregroundNotificationListener = _handleForegroundNotification;
    MerchantNavigationIntent.foregroundNotification.addListener(
      _foregroundNotificationListener,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNotificationCount();
    });
  }

  @override
  void dispose() {
    MerchantNavigationIntent.selectedTabIndex.removeListener(
      _selectedTabListener,
    );
    MerchantNavigationIntent.notificationsRefreshTick.removeListener(
      _notificationsRefreshListener,
    );
    MerchantNavigationIntent.foregroundNotification.removeListener(
      _foregroundNotificationListener,
    );
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    MerchantNavigationIntent.selectedTabIndex.value = index;
  }

  Future<void> _refreshNotificationCount() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().fetchUnreadCount(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _loadNotifications() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().fetchNotifications(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _markNotificationRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().markRead(
      apiClient: session.apiClient,
      token: token,
      notificationId: notificationId,
    );
  }

  Future<void> _showNotifications() async {
    await _loadNotifications();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _MerchantNotificationsSheet(
        onRefresh: _loadNotifications,
        onMarkAllRead: _markAllNotificationsRead,
        onSendTest: _sendTestNotification,
        onOpenNotification: _openNotification,
      ),
    );
  }

  Future<void> _markAllNotificationsRead() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().markAllRead(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _sendTestNotification() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().sendTestNotification(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _openNotification(MerchantNotification notification) async {
    await _markNotificationRead(notification.id);

    if (notification.opensOrder) {
      MerchantNavigationIntent.openOrder(
        orderId: notification.resolvedOrderId,
        notificationId: notification.id,
      );
      return;
    }

    MerchantNavigationIntent.openOrders();
  }

  void _handleForegroundNotification() {
    final intent = MerchantNavigationIntent.foregroundNotification.value;
    if (intent == null ||
        intent.sequence == _lastForegroundNotificationSequence) {
      return;
    }
    _lastForegroundNotificationSequence = intent.sequence;
    _refreshNotificationCount();

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          intent.body.isEmpty
              ? intent.title
              : '${intent.title}: ${intent.body}',
        ),
        behavior: SnackBarBehavior.floating,
        action: intent.orderId.isEmpty
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () {
                  _markNotificationRead(intent.notificationId);
                  MerchantNavigationIntent.openOrder(
                    orderId: intent.orderId,
                    notificationId: intent.notificationId,
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;

    if (wide) {
      return Scaffold(
        floatingActionButton: _MerchantNotificationButton(
          onPressed: _showNotifications,
        ),
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
      floatingActionButton: _MerchantNotificationButton(
        onPressed: _showNotifications,
      ),
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

class _MerchantNotificationButton extends StatelessWidget {
  const _MerchantNotificationButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Consumer<MerchantNotificationsProvider>(
      builder: (context, provider, _) {
        return FloatingActionButton.small(
          tooltip: 'Notifications',
          onPressed: onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              if (provider.unreadCount > 0)
                Positioned(
                  right: -7,
                  top: -7,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      provider.unreadCount > 99
                          ? '99+'
                          : provider.unreadCount.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MerchantNotificationsSheet extends StatelessWidget {
  const _MerchantNotificationsSheet({
    required this.onRefresh,
    required this.onMarkAllRead,
    required this.onSendTest,
    required this.onOpenNotification,
  });

  final Future<void> Function() onRefresh;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onSendTest;
  final _OpenNotificationCallback onOpenNotification;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send test',
                    onPressed: () => onSendTest(),
                    icon: const Icon(Icons.science_outlined),
                  ),
                  IconButton(
                    tooltip: 'Mark all read',
                    onPressed: () => onMarkAllRead(),
                    icon: const Icon(Icons.done_all_outlined),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => onRefresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<MerchantNotificationsProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.notifications.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.errorMessage != null &&
                      provider.notifications.isEmpty) {
                    return _NotificationStateMessage(
                      icon: Icons.error_outline,
                      title: 'Notifications could not be loaded',
                      message: provider.errorMessage!,
                      onPressed: onRefresh,
                    );
                  }

                  if (provider.notifications.isEmpty) {
                    return _NotificationStateMessage(
                      icon: Icons.notifications_none_outlined,
                      title: 'No notifications yet',
                      message: 'New paid orders will appear here.',
                      onPressed: onRefresh,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: onRefresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: provider.notifications.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final notification = provider.notifications[index];
                        return _NotificationTile(
                          notification: notification,
                          onTap: () async {
                            await onOpenNotification(notification);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final MerchantNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: unread
            ? Theme.of(context).colorScheme.primary.withAlpha(28)
            : Colors.grey.shade100,
        child: Icon(
          unread
              ? Icons.notifications_active_outlined
              : Icons.notifications_none_outlined,
          color: unread
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade600,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              notification.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          if (unread)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body.isNotEmpty)
              Text(
                notification.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (notification.createdAtLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                notification.createdAtLabel,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}

class _NotificationStateMessage extends StatelessWidget {
  const _NotificationStateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Icon(icon, size: 44, color: Colors.grey.shade500),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: () => onPressed(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
      ],
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
