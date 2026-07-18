import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_local_notification_service.dart';
import '../Common/merchant_local_notification_payload.dart';
import '../Common/merchant_navigation_intent.dart';
import '../Common/merchant_notification_alert_registry.dart';
import '../Common/merchant_permissions.dart';
import '../Controller/merchant_auto_print_service.dart';
import '../Controller/merchant_notification_service.dart';
import '../Controller/merchant_notifications_provider.dart';
import '../Controller/merchant_orders_provider.dart';
import '../Controller/merchant_printers_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Controller/merchant_settings_provider.dart';
import '../Models/merchant_notification.dart';
import '../LoginPage/merchant_password_change_page.dart';
import '../OrderPage/merchant_orders_page.dart';
import '../ProductPage/merchant_products_page.dart';
import '../RewardPage/merchant_rewards_page.dart';
import '../SettingsPage/merchant_settings_page.dart';

typedef _OpenNotificationCallback =
    Future<void> Function(MerchantNotification notification);
typedef _DeleteNotificationCallback =
    Future<void> Function(MerchantNotification notification);

class MerchantShellPage extends StatefulWidget {
  const MerchantShellPage({super.key});

  @override
  State<MerchantShellPage> createState() => _MerchantShellPageState();
}

class _MerchantShellPageState extends State<MerchantShellPage>
    with WidgetsBindingObserver {
  static const _notificationPollInterval = Duration(seconds: 15);
  static const _notificationPollLimit = 20;
  static const _notificationPollEventTypes = {
    'new_paid_order',
    'new_in_store_order',
    'customer_cancelled_order',
  };

  String _selectedDestinationId = MerchantNavigationIntent.ordersDestination;
  late final VoidCallback _selectedTabListener;
  late final VoidCallback _notificationsRefreshListener;
  late final VoidCallback _foregroundNotificationListener;
  int _lastForegroundNotificationSequence = 0;
  Timer? _notificationPollTimer;
  bool _backgroundPollCycleInFlight = false;
  bool _notificationPollInFlight = false;
  bool _notificationPollSeeded = false;
  bool _automaticPrintInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MerchantLocalNotificationService.instance.attachTapListener();
    _selectedDestinationId =
        MerchantNavigationIntent.selectedDestinationId.value;
    _selectedTabListener = () {
      final nextId = MerchantNavigationIntent.selectedDestinationId.value;
      if (!mounted || nextId == _selectedDestinationId) return;
      setState(() => _selectedDestinationId = nextId);
    };
    MerchantNavigationIntent.selectedDestinationId.addListener(
      _selectedTabListener,
    );
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
      _startNotificationPolling(refreshNotificationCount: true);
    });
  }

  @override
  void dispose() {
    _stopNotificationPolling();
    WidgetsBinding.instance.removeObserver(this);
    MerchantNavigationIntent.selectedDestinationId.removeListener(
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = context.read<MerchantSessionProvider>();
      session.resetBackgroundConnection();
      if (session.can(MerchantPermissions.ordersView)) {
        MerchantNavigationIntent.refreshOrders();
      }
      _startNotificationPolling(refreshNotificationCount: true);
      return;
    }
    _notificationPollSeeded = false;
    _stopNotificationPolling();
  }

  void _selectDestination(String destinationId) {
    setState(() => _selectedDestinationId = destinationId);
    MerchantNavigationIntent.selectedDestinationId.value = destinationId;
  }

  void _startNotificationPolling({bool refreshNotificationCount = false}) {
    if (!mounted) return;
    _notificationPollTimer?.cancel();
    unawaited(
      _runBackgroundPollCycle(
        refreshNotificationCount: refreshNotificationCount,
      ),
    );
    _notificationPollTimer = Timer.periodic(_notificationPollInterval, (_) {
      unawaited(_runBackgroundPollCycle());
    });
  }

  void _stopNotificationPolling() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = null;
  }

  Future<void> _runBackgroundPollCycle({
    bool refreshNotificationCount = false,
  }) async {
    if (_backgroundPollCycleInFlight || !mounted) return;
    _backgroundPollCycleInFlight = true;
    try {
      if (refreshNotificationCount) {
        await _refreshNotificationCount();
      }
      await _pollNotificationsForOrderEvents();
      await _pollAutomaticPrintJobs();
    } finally {
      _backgroundPollCycleInFlight = false;
    }
  }

  Future<void> _pollNotificationsForOrderEvents() async {
    if (_notificationPollInFlight || !mounted) return;

    final session = context.read<MerchantSessionProvider>();
    if (!session.can(MerchantPermissions.ordersView)) return;
    final token = session.token;
    if (token == null || token.isEmpty) return;
    final apiClient = session.backgroundApiClient;

    _notificationPollInFlight = true;
    try {
      final provider = context.read<MerchantNotificationsProvider>();
      final snapshot = await provider.fetchNotificationSnapshot(
        apiClient: apiClient,
        token: token,
        limit: _notificationPollLimit,
      );
      final watchedNotifications = snapshot
          .where(_isOrderEventNotification)
          .toList(growable: false);

      if (!_notificationPollSeeded) {
        await _markNotificationsAlerted(watchedNotifications);
        _notificationPollSeeded = true;
        return;
      }

      final newNotifications = <MerchantNotification>[];
      for (final notification in watchedNotifications) {
        final shouldAlert = await MerchantNotificationAlertRegistry.instance
            .shouldAlertNotification(notification);
        if (shouldAlert) {
          newNotifications.add(notification);
        }
      }

      if (newNotifications.isEmpty || !mounted) return;

      await provider.fetchNotifications(apiClient: apiClient, token: token);

      for (final notification in newNotifications.reversed) {
        await _handleForegroundOrderAlert(
          MerchantLocalNotificationPayload.fromNotification(notification),
          refreshNotifications: false,
          alreadyReserved: true,
        );
      }
    } catch (err) {
      debugPrint('Unable to poll merchant notifications: $err');
    } finally {
      _notificationPollInFlight = false;
    }
  }

  Future<void> _pollAutomaticPrintJobs() async {
    if (_automaticPrintInFlight || !mounted) return;

    final printersProvider = context.read<MerchantPrintersProvider>();
    final ordersProvider = context.read<MerchantOrdersProvider>();
    final settingsProvider = context.read<MerchantSettingsProvider>();
    final printer = printersProvider.defaultPrinter;
    if (printer == null ||
        printersProvider.isLoading ||
        printersProvider.isPrinting) {
      return;
    }

    final session = context.read<MerchantSessionProvider>();
    if (!session.can(MerchantPermissions.ordersView) ||
        !session.can(MerchantPermissions.ordersPrint)) {
      return;
    }
    final token = session.token;
    if (token == null || token.isEmpty) return;
    final apiClient = session.backgroundApiClient;

    _automaticPrintInFlight = true;
    try {
      final autoPrintService = MerchantAutoPrintService.instance;
      final job = await autoPrintService.claimNext(
        apiClient: apiClient,
        token: token,
      );
      if (job == null) return;

      if (await autoPrintService.wasPrinted(job.id)) {
        await autoPrintService.reportResult(
          apiClient: apiClient,
          token: token,
          job: job,
          success: true,
        );
        return;
      }

      final order = await ordersProvider.fetchOrderDetail(
        apiClient: apiClient,
        token: token,
        orderId: job.orderId,
      );
      if (order == null) {
        await autoPrintService.reportResult(
          apiClient: apiClient,
          token: token,
          job: job,
          success: false,
          error: ordersProvider.errorMessage ?? 'Unable to load order detail.',
        );
        return;
      }

      if (settingsProvider.buyerConfig == null && !settingsProvider.isLoading) {
        await settingsProvider.fetchBuyerConfig(
          apiClient: apiClient,
          token: token,
        );
      }

      final printed = await printersProvider.printOrder(
        order: order,
        printer: printer,
        storeProfile: settingsProvider.buyerConfig?.storeProfile,
      );
      if (!printed) {
        await autoPrintService.reportResult(
          apiClient: apiClient,
          token: token,
          job: job,
          success: false,
          error: printersProvider.errorMessage ?? 'Printer rejected the job.',
        );
        return;
      }

      await autoPrintService.markPrinted(job.id);
      await autoPrintService.reportResult(
        apiClient: apiClient,
        token: token,
        job: job,
        success: true,
      );
      debugPrint(
        '[AutoPrint] Printed ${job.orderId} on ${printer.displayName}.',
      );
    } catch (err) {
      debugPrint('[AutoPrint] Unable to process print job: $err');
    } finally {
      _automaticPrintInFlight = false;
    }
  }

  Future<void> _refreshNotificationCount() async {
    final session = context.read<MerchantSessionProvider>();
    if (!session.can(MerchantPermissions.ordersView)) return;
    final token = session.token;
    if (token == null || token.isEmpty) return;

    await context.read<MerchantNotificationsProvider>().fetchUnreadCount(
      apiClient: session.backgroundApiClient,
      token: token,
    );
  }

  Future<void> _loadNotifications() async {
    final session = context.read<MerchantSessionProvider>();
    if (!session.can(MerchantPermissions.ordersView)) return;
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
        onDeleteRead: _deleteReadNotifications,
        onSendTest: _sendTestNotification,
        onOpenNotification: _openNotification,
        onDeleteNotification: _deleteNotification,
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

  Future<void> _deleteNotification(MerchantNotification notification) async {
    if (notification.id.trim().isEmpty) return;
    unawaited(
      MerchantNotificationAlertRegistry.instance.markNotificationAlerted(
        notification,
      ),
    );
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    final provider = context.read<MerchantNotificationsProvider>();
    final success = await provider.deleteNotification(
      apiClient: session.apiClient,
      token: token,
      notificationId: notification.id,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Notification deleted.'
              : provider.errorMessage ?? 'Unable to delete notification.',
        ),
      ),
    );
  }

  Future<void> _deleteReadNotifications() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null || token.isEmpty) return;

    final provider = context.read<MerchantNotificationsProvider>();
    final success = await provider.deleteReadNotifications(
      apiClient: session.apiClient,
      token: token,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Read notifications deleted.'
              : provider.errorMessage ?? 'Unable to delete read notifications.',
        ),
      ),
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
    unawaited(
      MerchantNotificationAlertRegistry.instance.markNotificationAlerted(
        notification,
      ),
    );
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
    if (_isOrderEventType(intent.eventType)) {
      unawaited(
        _handleForegroundOrderAlert(
          MerchantLocalNotificationPayload(
            notificationId: intent.notificationId,
            eventType: intent.eventType,
            orderId: intent.orderId,
            title: intent.title,
            body: intent.body,
          ),
        ),
      );
      return;
    }

    _refreshNotificationCount();
    _showForegroundSnackBar(
      title: intent.title,
      body: intent.body,
      orderId: intent.orderId,
      notificationId: intent.notificationId,
    );
  }

  Future<void> _handleForegroundOrderAlert(
    MerchantLocalNotificationPayload payload, {
    bool refreshNotifications = true,
    bool alreadyReserved = false,
  }) async {
    if (!alreadyReserved) {
      final shouldAlert = await MerchantNotificationAlertRegistry.instance
          .shouldAlert(
            notificationId: payload.notificationId,
            eventType: payload.eventType,
            orderId: payload.orderId,
          );
      if (!shouldAlert) {
        await _refreshNotificationCount();
        return;
      }
    }
    if (!mounted) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (refreshNotifications && token != null && token.isNotEmpty) {
      await context.read<MerchantNotificationsProvider>().fetchNotifications(
        apiClient: session.backgroundApiClient,
        token: token,
      );
    } else {
      await _refreshNotificationCount();
    }

    unawaited(_pollAutomaticPrintJobs());

    await MerchantLocalNotificationService.instance.showPayload(payload);
    if (!mounted) return;

    _showForegroundSnackBar(
      title: payload.title,
      body: payload.body,
      orderId: payload.orderId,
      notificationId: payload.notificationId,
    );

    if (payload.orderId.isNotEmpty) {
      MerchantNavigationIntent.openOrder(
        orderId: payload.orderId,
        notificationId: payload.notificationId,
        markNotificationRead: false,
      );
      return;
    }

    MerchantNavigationIntent.openOrders();
  }

  void _showForegroundSnackBar({
    required String title,
    required String body,
    required String orderId,
    required String notificationId,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title: $body'),
        behavior: SnackBarBehavior.floating,
        action: orderId.isEmpty
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () {
                  _markNotificationRead(notificationId);
                  MerchantNavigationIntent.openOrder(
                    orderId: orderId,
                    notificationId: notificationId,
                  );
                },
              ),
      ),
    );
  }

  bool _isOrderEventType(String eventType) {
    return _notificationPollEventTypes.contains(eventType.trim().toLowerCase());
  }

  bool _isOrderEventNotification(MerchantNotification notification) {
    return _isOrderEventType(notification.eventType);
  }

  Future<void> _markNotificationsAlerted(
    Iterable<MerchantNotification> notifications,
  ) async {
    for (final notification in notifications) {
      await MerchantNotificationAlertRegistry.instance.markNotificationAlerted(
        notification,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;
    final session = context.watch<MerchantSessionProvider>();
    final destinations = _merchantDestinationsFor(session);
    var selectedIndex = destinations.indexWhere(
      (destination) => destination.id == _selectedDestinationId,
    );
    if (selectedIndex < 0) selectedIndex = 0;
    final selectedDestination = destinations[selectedIndex];
    final notificationButton = session.can(MerchantPermissions.ordersView)
        ? _MerchantNotificationButton(onPressed: _showNotifications)
        : null;

    if (wide) {
      return Scaffold(
        floatingActionButton: notificationButton,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                _selectDestination(destinations[index].id);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Icon(
                  Icons.storefront_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: selectedDestination.page),
          ],
        ),
      );
    }

    return Scaffold(
      body: selectedDestination.page,
      floatingActionButton: notificationButton,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          _selectDestination(destinations[index].id);
        },
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _MerchantDestination {
  const _MerchantDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

List<_MerchantDestination> _merchantDestinationsFor(
  MerchantSessionProvider session,
) {
  return [
    if (session.can(MerchantPermissions.ordersView))
      const _MerchantDestination(
        id: MerchantNavigationIntent.ordersDestination,
        label: 'Orders',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        page: MerchantOrdersPage(),
      ),
    if (session.can(MerchantPermissions.productsView))
      const _MerchantDestination(
        id: MerchantNavigationIntent.productsDestination,
        label: 'Products',
        icon: Icons.restaurant_menu_outlined,
        selectedIcon: Icons.restaurant_menu,
        page: MerchantProductsPage(),
      ),
    if (session.can(MerchantPermissions.rewardsView))
      const _MerchantDestination(
        id: MerchantNavigationIntent.rewardsDestination,
        label: 'Rewards',
        icon: Icons.card_giftcard_outlined,
        selectedIcon: Icons.card_giftcard,
        page: MerchantRewardsPage(),
      ),
    if (session.canAny(MerchantPermissions.settingsArea))
      const _MerchantDestination(
        id: MerchantNavigationIntent.settingsDestination,
        label: 'Settings',
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune,
        page: MerchantSettingsPage(),
      ),
    const _MerchantDestination(
      id: MerchantNavigationIntent.accountDestination,
      label: 'Account',
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle,
      page: _AccountPage(),
    ),
  ];
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
    required this.onDeleteRead,
    required this.onSendTest,
    required this.onOpenNotification,
    required this.onDeleteNotification,
  });

  final Future<void> Function() onRefresh;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onDeleteRead;
  final Future<void> Function() onSendTest;
  final _OpenNotificationCallback onOpenNotification;
  final _DeleteNotificationCallback onDeleteNotification;

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
                    tooltip: 'Clear read',
                    onPressed: () => onDeleteRead(),
                    icon: const Icon(Icons.delete_sweep_outlined),
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
                          onDelete: () => onDeleteNotification(notification),
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
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final MerchantNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
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
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MerchantPasswordChangePage(),
              ),
            ),
            icon: const Icon(Icons.password_outlined),
            label: const Text('Change password'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: session.isLoggingOut ? null : session.logout,
            icon: session.isLoggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: Text(session.isLoggingOut ? 'Logging out' : 'Logout'),
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
