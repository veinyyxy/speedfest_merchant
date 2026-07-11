import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_filter_preferences.dart';
import '../Common/merchant_navigation_intent.dart';
import '../Controller/merchant_notifications_provider.dart';
import '../Controller/merchant_orders_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_order.dart';
import 'merchant_order_detail_sheet.dart';

class MerchantOrdersPage extends StatefulWidget {
  const MerchantOrdersPage({super.key});

  @override
  State<MerchantOrdersPage> createState() => _MerchantOrdersPageState();
}

class _MerchantOrdersPageState extends State<MerchantOrdersPage> {
  static const _unacceptedReminderDelay = Duration(minutes: 1);
  static const _forcedVisibleOrderDuration = Duration(seconds: 4);

  bool _loaded = false;
  bool _initialLoadComplete = false;
  DateTime _now = DateTime.now();
  Timer? _unacceptedReminderTimer;
  Timer? _forcedVisibleOrderTimer;
  bool _businessFilterMode = false;
  String _fulfillmentFilter = 'all';
  String _statusFilter = 'all';
  String _businessFulfillmentFilter = 'delivery';
  String _businessStageFilter = 'active';
  String _businessQueueFilter = 'new_order';
  DateTimeRange? _dateRange = _todayDateRange();
  late final VoidCallback _ordersRefreshListener;
  late final VoidCallback _orderOpenIntentListener;
  final Map<String, GlobalKey> _orderCardKeys = {};
  int _lastHandledOrderOpenSequence = 0;
  String _highlightOrderId = '';
  int _highlightNonce = 0;
  String _forcedVisibleOrderId = '';

  @override
  void initState() {
    super.initState();
    _ordersRefreshListener = () {
      if (!mounted) return;
      _fetchOrders();
    };
    MerchantNavigationIntent.ordersRefreshTick.addListener(
      _ordersRefreshListener,
    );
    _orderOpenIntentListener = () {
      _handleOrderOpenIntent();
    };
    MerchantNavigationIntent.orderOpenIntent.addListener(
      _orderOpenIntentListener,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleOrderOpenIntent();
    });
    _unacceptedReminderTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    MerchantNavigationIntent.ordersRefreshTick.removeListener(
      _ordersRefreshListener,
    );
    MerchantNavigationIntent.orderOpenIntent.removeListener(
      _orderOpenIntentListener,
    );
    _unacceptedReminderTimer?.cancel();
    _forcedVisibleOrderTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFiltersAndFetch());
  }

  Future<void> _loadFiltersAndFetch() async {
    final filterMode = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersFilterMode,
    );
    final fulfillmentFilter = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersFulfillmentFilter,
    );
    final statusFilter = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersStatusFilter,
    );
    final businessFulfillmentFilter =
        await MerchantFilterPreferences.readString(
          MerchantFilterPreferences.ordersBusinessFulfillmentFilter,
        );
    final businessStageFilter = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersBusinessStageFilter,
    );
    final businessQueueFilter = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersBusinessQueueFilter,
    );
    final dateRange = await _loadSavedDateRange();
    if (!mounted) return;

    final nextFulfillment = _isFulfillmentFilter(fulfillmentFilter)
        ? fulfillmentFilter!
        : 'all';
    final nextStatus =
        statusFilter != null &&
            _statusAllowedForFulfillment(nextFulfillment, statusFilter)
        ? statusFilter
        : 'all';
    final nextBusinessMode = filterMode == 'business';
    final nextBusinessFulfillment =
        _isBusinessFulfillmentFilter(businessFulfillmentFilter)
        ? businessFulfillmentFilter!
        : _isBusinessFulfillmentFilter(nextFulfillment)
        ? nextFulfillment
        : 'delivery';
    final nextBusinessStage = _isBusinessStageFilter(businessStageFilter)
        ? businessStageFilter!
        : 'active';
    final nextBusinessQueue =
        businessQueueFilter != null &&
            _businessQueueAllowedForFulfillment(
              nextBusinessFulfillment,
              businessQueueFilter,
            )
        ? businessQueueFilter
        : 'new_order';

    setState(() {
      _businessFilterMode = nextBusinessMode;
      _fulfillmentFilter = nextFulfillment;
      _statusFilter = nextStatus;
      _businessFulfillmentFilter = nextBusinessFulfillment;
      _businessStageFilter = nextBusinessStage;
      _businessQueueFilter = nextBusinessQueue;
      _dateRange = dateRange;
    });

    await _fetchOrders();
    if (!mounted) return;
    _initialLoadComplete = true;
    await _handleOrderOpenIntent();
  }

  Future<DateTimeRange?> _loadSavedDateRange() async {
    final dateFilter = await MerchantFilterPreferences.readString(
      MerchantFilterPreferences.ordersDateFilter,
    );
    if (dateFilter == 'all') return null;

    if (dateFilter == 'custom') {
      final startText = await MerchantFilterPreferences.readString(
        MerchantFilterPreferences.ordersDateStart,
      );
      final endText = await MerchantFilterPreferences.readString(
        MerchantFilterPreferences.ordersDateEnd,
      );
      final start = DateTime.tryParse(startText ?? '');
      final end = DateTime.tryParse(endText ?? '');
      if (start != null && end != null && !end.isBefore(start)) {
        return DateTimeRange(start: _startOfDay(start), end: _endOfDay(end));
      }
      return _todayDateRange();
    }

    final shortcut = _dateShortcutByKey(dateFilter ?? 'today');
    return shortcut == null
        ? _todayDateRange()
        : _dateRangeForShortcut(shortcut);
  }

  Future<void> _fetchOrders() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantOrdersProvider>().fetchOrders(
      apiClient: session.apiClient,
      token: token,
      dateFrom: _queryDateFrom(),
      dateTo: _queryDateTo(),
    );
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _startOfDay(_dateRange?.start ?? now),
        end: _startOfDay(_dateRange?.end ?? now),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _dateRange = _dateRangeForCustom(picked);
    });
    await _saveCustomDateRange(_dateRange);
    await _fetchOrders();
  }

  Future<void> _selectDateShortcut(_DateShortcut shortcut) async {
    setState(() => _dateRange = _dateRangeForShortcut(shortcut));
    await _saveDateShortcut(shortcut);
    await _fetchOrders();
  }

  Future<void> _setFulfillmentFilter(String type) async {
    setState(() {
      _fulfillmentFilter = type;
      if (!_statusAllowedForFulfillment(type, _statusFilter)) {
        _statusFilter = 'all';
      }
    });
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersFulfillmentFilter,
      _fulfillmentFilter,
    );
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersStatusFilter,
      _statusFilter,
    );
  }

  Future<void> _setStatusFilter(String status) async {
    setState(() => _statusFilter = status);
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersStatusFilter,
      status,
    );
  }

  Future<void> _setBusinessFilterMode(bool enabled) async {
    setState(() => _businessFilterMode = enabled);
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersFilterMode,
      enabled ? 'business' : 'debug',
    );
    await _fetchOrders();
  }

  Future<void> _setBusinessFulfillmentFilter(String type) async {
    setState(() {
      _businessFulfillmentFilter = type;
      if (!_businessQueueAllowedForFulfillment(type, _businessQueueFilter)) {
        _businessQueueFilter = 'new_order';
      }
    });
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersBusinessFulfillmentFilter,
      _businessFulfillmentFilter,
    );
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersBusinessQueueFilter,
      _businessQueueFilter,
    );
  }

  Future<void> _setBusinessStageFilter(String stage) async {
    setState(() => _businessStageFilter = stage);
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersBusinessStageFilter,
      stage,
    );
    await _fetchOrders();
  }

  Future<void> _setBusinessQueueFilter(String queue) async {
    setState(() => _businessQueueFilter = queue);
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersBusinessQueueFilter,
      queue,
    );
  }

  Future<void> _saveDateShortcut(_DateShortcut shortcut) async {
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersDateFilter,
      shortcut.key,
    );
    if (shortcut.days == null) {
      await MerchantFilterPreferences.remove(
        MerchantFilterPreferences.ordersDateStart,
      );
      await MerchantFilterPreferences.remove(
        MerchantFilterPreferences.ordersDateEnd,
      );
    }
  }

  Future<void> _saveCustomDateRange(DateTimeRange? range) async {
    if (range == null) {
      await _saveDateShortcut(_dateShortcuts.first);
      return;
    }
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersDateFilter,
      'custom',
    );
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersDateStart,
      range.start.toIso8601String(),
    );
    await MerchantFilterPreferences.writeString(
      MerchantFilterPreferences.ordersDateEnd,
      range.end.toIso8601String(),
    );
  }

  DateTime? _queryDateFrom() {
    if (!_businessFilterMode) return _dateRange?.start;

    final today = DateTime.now();
    return switch (_businessStageFilter) {
      'active' => _startOfDay(today),
      'upcoming' => _startOfDay(today.add(const Duration(days: 1))),
      'history' => null,
      _ => _startOfDay(today),
    };
  }

  DateTime? _queryDateTo() {
    if (!_businessFilterMode) return _dateRange?.end;

    final today = DateTime.now();
    return switch (_businessStageFilter) {
      'active' => _endOfDay(today),
      'upcoming' => null,
      'history' => _endOfDay(today.subtract(const Duration(days: 1))),
      _ => _endOfDay(today),
    };
  }

  List<MerchantOrder> _filteredOrders(List<MerchantOrder> orders) {
    if (_businessFilterMode) {
      return orders
          .where(
            (order) =>
                order.id == _forcedVisibleOrderId ||
                _matchesBusinessFulfillmentFilter(order) &&
                    _matchesBusinessStageFilter(order) &&
                    _matchesBusinessQueueFilter(order),
          )
          .toList(growable: false);
    }

    return orders
        .where(
          (order) =>
              _matchesFulfillmentFilter(order) && _matchesStatusFilter(order),
        )
        .toList(growable: false);
  }

  GlobalKey _keyForOrder(String orderId) {
    return _orderCardKeys.putIfAbsent(orderId, GlobalKey.new);
  }

  bool _matchesFulfillmentFilter(MerchantOrder order) {
    if (_fulfillmentFilter == 'all') return true;
    return order.normalizedFulfillmentType == _fulfillmentFilter;
  }

  bool _matchesBusinessFulfillmentFilter(MerchantOrder order) {
    return order.normalizedFulfillmentType == _businessFulfillmentFilter;
  }

  bool _matchesBusinessStageFilter(MerchantOrder order) {
    final createdAt = order.createdAt?.toLocal();
    if (createdAt == null) return _businessStageFilter == 'active';

    final today = DateTime.now();
    final todayStart = _startOfDay(today);
    final todayEnd = _endOfDay(today);

    return switch (_businessStageFilter) {
      'active' =>
        !createdAt.isBefore(todayStart) && !createdAt.isAfter(todayEnd),
      'upcoming' => createdAt.isAfter(todayEnd),
      'history' => createdAt.isBefore(todayStart),
      _ => !createdAt.isBefore(todayStart) && !createdAt.isAfter(todayEnd),
    };
  }

  bool _matchesBusinessQueueFilter(MerchantOrder order) {
    final status = order.normalizedStatus;
    return switch (_businessQueueFilter) {
      'new_order' =>
        (order.isAwaitingInStoreCollection && status == 'created') ||
            status == 'paid' ||
            status == 'accepted' ||
            status == 'preparing',
      'awaiting_collection' => order.isAwaitingInStoreCollection,
      'ready' => status == 'ready',
      'on_the_way' =>
        order.isDelivery &&
            _businessFulfillmentFilter == 'delivery' &&
            status == 'on_the_way',
      'delivered' =>
        order.isDelivery &&
            _businessFulfillmentFilter == 'delivery' &&
            status == 'delivered',
      'completed' =>
        !order.isDelivery &&
            _businessFulfillmentFilter != 'delivery' &&
            status == 'completed',
      _ => false,
    };
  }

  bool _matchesStatusFilter(MerchantOrder order) {
    if (_statusFilter == 'all') return true;

    if (_statusFilter == 'pending_payment') {
      return order.isPendingPayment;
    }
    if (_statusFilter == 'awaiting_collection') {
      return order.isAwaitingInStoreCollection;
    }

    return order.normalizedStatus == _statusFilter;
  }

  bool _needsAcceptanceReminder(MerchantOrder order) {
    final needsAcceptance =
        order.normalizedStatus == 'paid' ||
        (order.normalizedStatus == 'created' &&
            order.isAwaitingInStoreCollection);
    if (!needsAcceptance) return false;

    final referenceTime = order.updatedAt ?? order.createdAt;
    if (referenceTime == null) return false;

    final elapsed = _now.difference(referenceTime.toLocal());
    return !elapsed.isNegative && elapsed >= _unacceptedReminderDelay;
  }

  Future<void> _updateStatus(MerchantOrder order, String status) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final ordersProvider = context.read<MerchantOrdersProvider>();
    final ok = await ordersProvider.updateOrderStatus(
      apiClient: session.apiClient,
      token: token,
      orderId: order.id,
      status: status,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${order.displayId} moved to ${_humanize(status)}.'
              : ordersProvider.errorMessage ?? 'Order could not be updated.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (ok) {
      await _fetchOrders();
    }
  }

  Future<void> _refundOrder(MerchantOrder order) async {
    final request = await showDialog<_RefundRequest>(
      context: context,
      builder: (_) => _RefundOrderDialog(order: order),
    );
    if (request == null || !mounted) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final ordersProvider = context.read<MerchantOrdersProvider>();
    final ok = await ordersProvider.refundOrder(
      apiClient: session.apiClient,
      token: token,
      orderId: order.id,
      amount: request.amount,
      note: request.note,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Refund request submitted for ${order.displayId}.'
              : ordersProvider.errorMessage ?? 'Order could not be refunded.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? null : Colors.red.shade700,
      ),
    );

    if (ok) {
      await _fetchOrders();
    }
  }

  Future<void> _collectInStorePayment(MerchantOrder order) async {
    final request = await showDialog<_InStoreCollectionRequest>(
      context: context,
      builder: (_) => _InStoreCollectionDialog(order: order),
    );
    if (request == null || !mounted) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final ordersProvider = context.read<MerchantOrdersProvider>();
    final collectedOrder = await ordersProvider.collectInStorePayment(
      apiClient: session.apiClient,
      token: token,
      orderId: order.id,
      paymentMethod: request.paymentMethod,
      collectionReference: request.collectionReference,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          collectedOrder == null
              ? ordersProvider.errorMessage ??
                    'In-store payment could not be recorded.'
              : '${order.displayId} payment recorded as ${request.methodLabel}.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: collectedOrder == null ? Colors.red.shade700 : null,
      ),
    );

    if (collectedOrder != null) {
      await _fetchOrders();
    }
  }

  Future<void> _showDetail(MerchantOrder order) async {
    await _showDetailByOrderId(order.id);
  }

  Future<void> _showDetailByOrderId(String orderId) async {
    final detail = await _fetchOrderDetailById(orderId);
    if (!mounted || detail == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => MerchantOrderDetailSheet(
        order: detail,
        onSyncPaymentRecords: detail.isInStorePayment
            ? null
            : _syncPaymentRecords,
      ),
    );
  }

  Future<MerchantOrder?> _fetchOrderDetailById(String orderId) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return null;

    return context.read<MerchantOrdersProvider>().fetchOrderDetail(
      apiClient: session.apiClient,
      token: token,
      orderId: orderId,
    );
  }

  Future<void> _handleOrderOpenIntent() async {
    if (!_initialLoadComplete) return;

    final intent = MerchantNavigationIntent.orderOpenIntent.value;
    if (intent == null ||
        intent.sequence == _lastHandledOrderOpenSequence ||
        intent.orderId.isEmpty) {
      return;
    }
    _lastHandledOrderOpenSequence = intent.sequence;

    if (intent.refreshOrders) {
      await _fetchOrders();
    }
    if (intent.markNotificationRead) {
      await _markNotificationRead(intent.notificationId);
    }
    final order = await _fetchOrderDetailById(intent.orderId);
    if (!mounted || order == null) return;

    _showOrderInCurrentList(order);
  }

  Future<void> _markNotificationRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantNotificationsProvider>().markRead(
      apiClient: session.apiClient,
      token: token,
      notificationId: notificationId,
    );
  }

  Future<MerchantOrder?> _syncPaymentRecords(MerchantOrder order) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return null;

    final ordersProvider = context.read<MerchantOrdersProvider>();
    final syncedOrder = await ordersProvider.syncPaymentRecords(
      apiClient: session.apiClient,
      token: token,
      orderId: order.id,
    );
    if (!mounted) return syncedOrder;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          syncedOrder == null
              ? ordersProvider.errorMessage ??
                    'Payment records could not be synced.'
              : 'Payment records synced for ${order.displayId}.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: syncedOrder == null ? Colors.red.shade700 : null,
      ),
    );

    return syncedOrder;
  }

  String _ordersDateScopeLabel() {
    if (!_businessFilterMode) return _dateRangeLabel(_dateRange);
    return _businessStageLabel(_businessStageFilter);
  }

  void _showOrderInCurrentList(MerchantOrder order) {
    final nextFulfillmentFilter = _fulfillmentFilterForOrder(order);
    final nextStatusFilter = _statusFilterForOrder(order);
    final nextBusinessFulfillmentFilter = _businessFulfillmentForOrder(order);
    final nextBusinessStageFilter = _businessStageForOrder(order);
    final nextBusinessQueueFilter = _businessQueueForOrder(order);
    final isBusinessMode = _businessFilterMode;

    setState(() {
      if (_businessFilterMode) {
        _businessFulfillmentFilter = nextBusinessFulfillmentFilter;
        _businessStageFilter = nextBusinessStageFilter;
        if (nextBusinessQueueFilter != null) {
          _businessQueueFilter = nextBusinessQueueFilter;
        } else if (!_businessQueueAllowedForFulfillment(
          nextBusinessFulfillmentFilter,
          _businessQueueFilter,
        )) {
          _businessQueueFilter = 'new_order';
        }
        _forcedVisibleOrderId = order.id;
      } else {
        _fulfillmentFilter = nextFulfillmentFilter;
        _statusFilter = nextStatusFilter;
        _forcedVisibleOrderId = '';
      }
      _highlightOrderId = order.id;
      _highlightNonce += 1;
    });

    if (isBusinessMode) {
      _scheduleForcedVisibleOrderClear(order.id);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToOrder(order.id);
    });
  }

  void _scheduleForcedVisibleOrderClear(String orderId) {
    _forcedVisibleOrderTimer?.cancel();
    _forcedVisibleOrderTimer = Timer(_forcedVisibleOrderDuration, () {
      if (!mounted || _forcedVisibleOrderId != orderId) return;
      setState(() => _forcedVisibleOrderId = '');
    });
  }

  String _fulfillmentFilterForOrder(MerchantOrder order) {
    if (_matchesFulfillmentFilter(order)) return _fulfillmentFilter;
    final fulfillment = order.normalizedFulfillmentType;
    return _isFulfillmentFilter(fulfillment) ? fulfillment : 'all';
  }

  String _statusFilterForOrder(MerchantOrder order) {
    if (_matchesStatusFilter(order)) return _statusFilter;
    final nextStatus = order.isPendingPayment
        ? 'pending_payment'
        : order.isAwaitingInStoreCollection
        ? 'awaiting_collection'
        : order.normalizedStatus;
    final nextFulfillment = _fulfillmentFilterForOrder(order);
    return _statusAllowedForFulfillment(nextFulfillment, nextStatus)
        ? nextStatus
        : 'all';
  }

  String _businessFulfillmentForOrder(MerchantOrder order) {
    final fulfillment = order.normalizedFulfillmentType;
    return _isBusinessFulfillmentFilter(fulfillment)
        ? fulfillment
        : _businessFulfillmentFilter;
  }

  String _businessStageForOrder(MerchantOrder order) {
    final createdAt = order.createdAt?.toLocal();
    if (createdAt == null) return 'active';

    final today = DateTime.now();
    final todayStart = _startOfDay(today);
    final todayEnd = _endOfDay(today);
    if (createdAt.isBefore(todayStart)) return 'history';
    if (createdAt.isAfter(todayEnd)) return 'upcoming';
    return 'active';
  }

  String? _businessQueueForOrder(MerchantOrder order) {
    final status = order.normalizedStatus;
    final fulfillment = _businessFulfillmentForOrder(order);
    if (order.isAwaitingInStoreCollection && status == 'completed') {
      return 'awaiting_collection';
    }
    if (order.isAwaitingInStoreCollection && status == 'created') {
      return 'new_order';
    }
    if (status == 'paid' || status == 'accepted' || status == 'preparing') {
      return 'new_order';
    }
    if (status == 'ready') return 'ready';
    if (fulfillment == 'delivery' && status == 'on_the_way') {
      return 'on_the_way';
    }
    if (fulfillment == 'delivery' && status == 'delivered') {
      return 'delivered';
    }
    if (fulfillment != 'delivery' && status == 'completed') {
      return 'completed';
    }
    return null;
  }

  void _scrollToOrder(String orderId, {int attempt = 0}) {
    final context = _orderCardKeys[orderId]?.currentContext;
    if (context == null) {
      if (attempt < 3) {
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          _scrollToOrder(orderId, attempt: attempt + 1);
        });
      }
      return;
    }

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantOrdersProvider>();
    final orders = _filteredOrders(provider.orders);
    final statusFilters = _businessFilterMode
        ? const <_OrderFilter>[]
        : _statusFiltersForFulfillment(_fulfillmentFilter);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Orders'),
            const SizedBox(width: 10),
            Tooltip(
              message: _businessFilterMode
                  ? 'Business categories'
                  : 'Debug categories',
              child: Switch.adaptive(
                value: _businessFilterMode,
                onChanged: _setBusinessFilterMode,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : _fetchOrders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_businessFilterMode) ...[
            _BusinessFulfillmentFilterBar(
              selectedType: _businessFulfillmentFilter,
              onSelected: _setBusinessFulfillmentFilter,
            ),
            _BusinessStageFilterBar(
              selectedStage: _businessStageFilter,
              onSelected: _setBusinessStageFilter,
            ),
            _BusinessQueueFilterBar(
              filters: _businessQueueFiltersForFulfillment(
                _businessFulfillmentFilter,
              ),
              selectedQueue: _businessQueueFilter,
              onSelected: _setBusinessQueueFilter,
            ),
          ] else ...[
            _DateRangeFilterBar(
              selectedDateShortcut: _shortcutForRange(_dateRange),
              customDateLabel: _dateRangeLabel(_dateRange),
              onSelectDateShortcut: _selectDateShortcut,
              onSelectCustomDate: _selectDateRange,
            ),
            _FulfillmentFilterBar(
              selectedType: _fulfillmentFilter,
              onSelected: _setFulfillmentFilter,
            ),
            _StatusFilterBar(
              filters: statusFilters,
              selectedStatus: _statusFilter,
              onSelected: _setStatusFilter,
            ),
          ],
          Expanded(
            child: _OrdersBody(
              provider: provider,
              orders: orders,
              dateRangeLabel: _ordersDateScopeLabel(),
              orderKeyFor: _keyForOrder,
              highlightOrderId: _highlightOrderId,
              highlightNonce: _highlightNonce,
              needsAcceptanceReminder: _needsAcceptanceReminder,
              onRefresh: _fetchOrders,
              onOpenDetail: _showDetail,
              onUpdateStatus: _updateStatus,
              onRefund: _refundOrder,
              onCollectInStorePayment: _collectInStorePayment,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeFilterBar extends StatelessWidget {
  const _DateRangeFilterBar({
    required this.selectedDateShortcut,
    required this.customDateLabel,
    required this.onSelectDateShortcut,
    required this.onSelectCustomDate,
  });

  final _DateShortcut? selectedDateShortcut;
  final String customDateLabel;
  final ValueChanged<_DateShortcut> onSelectDateShortcut;
  final VoidCallback onSelectCustomDate;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'Date',
      children: [
        for (final shortcut in _dateShortcuts)
          ChoiceChip(
            label: Text(shortcut.label),
            selected: selectedDateShortcut?.key == shortcut.key,
            onSelected: (_) => onSelectDateShortcut(shortcut),
          ),
        _CustomDateChip(
          selected: selectedDateShortcut == null,
          label: customDateLabel,
          onPressed: onSelectCustomDate,
        ),
      ],
    );
  }
}

class _FulfillmentFilterBar extends StatelessWidget {
  const _FulfillmentFilterBar({
    required this.selectedType,
    required this.onSelected,
  });

  final String selectedType;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'Type',
      children: [
        for (final filter in _fulfillmentFilters)
          ChoiceChip(
            label: Text(filter.label),
            selected: selectedType == filter.type,
            onSelected: (_) => onSelected(filter.type),
          ),
      ],
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.filters,
    required this.selectedStatus,
    required this.onSelected,
  });

  final List<_OrderFilter> filters;
  final String selectedStatus;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'Status',
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter.label),
            selected: selectedStatus == filter.status,
            onSelected: (_) => onSelected(filter.status),
          ),
      ],
    );
  }
}

class _BusinessFulfillmentFilterBar extends StatelessWidget {
  const _BusinessFulfillmentFilterBar({
    required this.selectedType,
    required this.onSelected,
  });

  final String selectedType;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'Type',
      children: [
        for (final filter in _businessFulfillmentFilters)
          ChoiceChip(
            label: Text(filter.label),
            selected: selectedType == filter.type,
            onSelected: (_) => onSelected(filter.type),
          ),
      ],
    );
  }
}

class _BusinessStageFilterBar extends StatelessWidget {
  const _BusinessStageFilterBar({
    required this.selectedStage,
    required this.onSelected,
  });

  final String selectedStage;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'When',
      children: [
        for (final filter in _businessStageFilters)
          ChoiceChip(
            label: Text(filter.label),
            selected: selectedStage == filter.key,
            onSelected: (_) => onSelected(filter.key),
          ),
      ],
    );
  }
}

class _BusinessQueueFilterBar extends StatelessWidget {
  const _BusinessQueueFilterBar({
    required this.filters,
    required this.selectedQueue,
    required this.onSelected,
  });

  final List<_BusinessFilter> filters;
  final String selectedQueue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _FilterRow(
      label: 'Queue',
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter.label),
            selected: selectedQueue == filter.key,
            onSelected: (_) => onSelected(filter.key),
          ),
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => children[index],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomDateChip extends StatelessWidget {
  const _CustomDateChip({
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        Icons.calendar_month_outlined,
        size: 18,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      label: Text(selected ? label : 'Custom'),
      side: selected
          ? BorderSide(color: Theme.of(context).colorScheme.primary)
          : null,
      onPressed: onPressed,
    );
  }
}

class _FulfillmentFilter {
  const _FulfillmentFilter(this.type, this.label);

  final String type;
  final String label;
}

const _fulfillmentFilters = <_FulfillmentFilter>[
  _FulfillmentFilter('all', 'All'),
  _FulfillmentFilter('delivery', 'Delivery'),
  _FulfillmentFilter('takeout', 'Takeout'),
  _FulfillmentFilter('dine_in', 'Dine-in'),
];

class _OrderFilter {
  const _OrderFilter(this.status, this.label);

  final String status;
  final String label;
}

class _BusinessFilter {
  const _BusinessFilter(this.key, this.label);

  final String key;
  final String label;
}

const _businessFulfillmentFilters = <_FulfillmentFilter>[
  _FulfillmentFilter('delivery', 'Delivery'),
  _FulfillmentFilter('takeout', 'Takeout'),
  _FulfillmentFilter('dine_in', 'Dine-in'),
];

const _businessStageFilters = <_BusinessFilter>[
  _BusinessFilter('active', 'Active'),
  _BusinessFilter('upcoming', 'Upcoming'),
  _BusinessFilter('history', 'History'),
];

const _businessDeliveryQueueFilters = <_BusinessFilter>[
  _BusinessFilter('new_order', 'New Order'),
  _BusinessFilter('ready', 'Ready'),
  _BusinessFilter('on_the_way', 'On the way'),
  _BusinessFilter('delivered', 'Delivered'),
];

const _businessNonDeliveryQueueFilters = <_BusinessFilter>[
  _BusinessFilter('new_order', 'New Order'),
  _BusinessFilter('ready', 'Ready'),
  _BusinessFilter('awaiting_collection', 'Collect Payment'),
  _BusinessFilter('completed', 'Completed'),
];

class _DateShortcut {
  const _DateShortcut(this.key, this.label, this.days);

  final String key;
  final String label;
  final int? days;
}

const _dateShortcuts = <_DateShortcut>[
  _DateShortcut('all', 'All', null),
  _DateShortcut('today', 'Today', 1),
  _DateShortcut('three_days', '3 days', 3),
  _DateShortcut('one_week', '1 week', 7),
  _DateShortcut('one_month', '1 month', 30),
  _DateShortcut('three_months', '3 months', 90),
  _DateShortcut('six_months', '6 months', 180),
];

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({
    required this.provider,
    required this.orders,
    required this.dateRangeLabel,
    required this.orderKeyFor,
    required this.highlightOrderId,
    required this.highlightNonce,
    required this.needsAcceptanceReminder,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onUpdateStatus,
    required this.onRefund,
    required this.onCollectInStorePayment,
  });

  final MerchantOrdersProvider provider;
  final List<MerchantOrder> orders;
  final String dateRangeLabel;
  final GlobalKey Function(String orderId) orderKeyFor;
  final String highlightOrderId;
  final int highlightNonce;
  final bool Function(MerchantOrder order) needsAcceptanceReminder;
  final Future<void> Function() onRefresh;
  final ValueChanged<MerchantOrder> onOpenDetail;
  final void Function(MerchantOrder order, String status) onUpdateStatus;
  final ValueChanged<MerchantOrder> onRefund;
  final ValueChanged<MerchantOrder> onCollectInStorePayment;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading && provider.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null && provider.orders.isEmpty) {
      return _StateMessage(
        icon: Icons.error_outline,
        title: 'Orders could not be loaded',
        message: provider.errorMessage!,
        onPressed: onRefresh,
      );
    }

    if (provider.orders.isEmpty) {
      return _StateMessage(
        icon: Icons.receipt_long_outlined,
        title: 'No orders here',
        message: 'No orders were found for $dateRangeLabel.',
        onPressed: onRefresh,
      );
    }

    if (orders.isEmpty) {
      return _StateMessage(
        icon: Icons.filter_list_off_outlined,
        title: 'No matching orders',
        message: 'Try another order type, status, or date range.',
        onPressed: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final order in orders)
            _OrderCard(
              key: orderKeyFor(order.id),
              order: order,
              isUpdating: provider.isUpdating,
              highlight: order.id == highlightOrderId,
              highlightNonce: highlightNonce,
              needsAcceptanceReminder: needsAcceptanceReminder(order),
              onOpenDetail: () => onOpenDetail(order),
              onUpdateStatus: (status) => onUpdateStatus(order, status),
              onRefund: () => onRefund(order),
              onCollectInStorePayment: () => onCollectInStorePayment(order),
            ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.order,
    required this.isUpdating,
    required this.highlight,
    required this.highlightNonce,
    required this.needsAcceptanceReminder,
    required this.onOpenDetail,
    required this.onUpdateStatus,
    required this.onRefund,
    required this.onCollectInStorePayment,
  });

  final MerchantOrder order;
  final bool isUpdating;
  final bool highlight;
  final int highlightNonce;
  final bool needsAcceptanceReminder;
  final VoidCallback onOpenDetail;
  final ValueChanged<String> onUpdateStatus;
  final VoidCallback onRefund;
  final VoidCallback onCollectInStorePayment;

  @override
  Widget build(BuildContext context) {
    final nextAction = _primaryActionFor(order);
    final destructiveActions = _destructiveActionsFor(order);

    return TweenAnimationBuilder<double>(
      key: ValueKey('order-highlight-${order.id}-$highlightNonce-$highlight'),
      tween: Tween<double>(begin: highlight ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, highlightValue, _) {
        final borderColor = Color.lerp(
          needsAcceptanceReminder ? Colors.red.shade700 : Colors.grey.shade300,
          Colors.green.shade600,
          highlightValue,
        )!;
        final borderWidth = highlightValue > 0
            ? 2.2
            : needsAcceptanceReminder
            ? 2.0
            : 1.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.displayId,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.createdAtLabel,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _StatusChip(order: order),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.storefront_outlined,
                      label: order.fulfillmentLabel,
                    ),
                    _InfoPill(
                      icon: Icons.shopping_bag_outlined,
                      label:
                          '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                    ),
                    _InfoPill(
                      icon: Icons.payments_outlined,
                      label:
                          '${order.currency} \$${order.totalAmount.toStringAsFixed(2)}',
                    ),
                    _InfoPill(
                      icon: Icons.credit_card_outlined,
                      label: order.paymentDetailStatusLabel,
                    ),
                    if (order.hasRefund)
                      _InfoPill(
                        icon: Icons.reply_all_outlined,
                        label:
                            'Refunded: ${order.currency} \$${order.refundedAmount.toStringAsFixed(2)}',
                      ),
                  ],
                ),
                if (order.customerPhone.isNotEmpty ||
                    order.customerName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    [
                      order.customerName,
                      order.customerPhone,
                    ].where((value) => value.isNotEmpty).join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onOpenDetail,
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Details'),
                    ),
                    const Spacer(),
                    if (order.canCollectInStorePayment)
                      IconButton(
                        tooltip: 'Collect payment',
                        onPressed: isUpdating ? null : onCollectInStorePayment,
                        icon: const Icon(Icons.point_of_sale_outlined),
                        color: Colors.green.shade700,
                      ),
                    for (final action in destructiveActions) ...[
                      TextButton(
                        onPressed: isUpdating
                            ? null
                            : action.status == 'refunded'
                            ? onRefund
                            : () => onUpdateStatus(action.status),
                        style: TextButton.styleFrom(
                          foregroundColor: action.status == 'cancelled'
                              ? Colors.red.shade700
                              : Colors.orange.shade800,
                        ),
                        child: Text(action.label),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (nextAction != null)
                      FilledButton(
                        onPressed: isUpdating
                            ? null
                            : () => onUpdateStatus(nextAction.status),
                        child: Text(nextAction.label),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.grey.shade800)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.order});

  final MerchantOrder order;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(
      order.isPendingPayment
          ? 'pending_payment'
          : order.isAwaitingInStoreCollection
          ? 'awaiting_collection'
          : order.status,
      Theme.of(context).colorScheme.primary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        order.displayStatusLabel,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _RefundOrderDialog extends StatefulWidget {
  const _RefundOrderDialog({required this.order});

  final MerchantOrder order;

  @override
  State<_RefundOrderDialog> createState() => _RefundOrderDialogState();
}

class _RefundOrderDialogState extends State<_RefundOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController(text: 'Merchant refund');
  bool _customAmount = false;

  double get _maxAmount {
    final remaining = widget.order.refundableAmount;
    if (remaining > 0) return remaining;
    final fallback = widget.order.totalAmount - widget.order.refundedAmount;
    return fallback > 0 ? fallback : 0;
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = _maxAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxAmount = _maxAmount;
    return AlertDialog(
      title: const Text('Refund order'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.order.displayId} refundable amount: '
                '${widget.order.currency} \$${maxAmount.toStringAsFixed(2)}',
              ),
              if (widget.order.refundedAmount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Already refunded: ${widget.order.currency} \$${widget.order.refundedAmount.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 12),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Refund remaining amount'),
                value: false,
                groupValue: _customAmount,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _customAmount = value);
                },
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Custom amount'),
                value: true,
                groupValue: _customAmount,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _customAmount = value);
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                enabled: _customAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Refund amount',
                  prefixText: '${widget.order.currency} \$',
                  border: const OutlineInputBorder(),
                ),
                validator: _customAmount
                    ? (value) => _refundAmountValidator(value, maxAmount)
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: maxAmount <= 0
              ? null
              : () {
                  final valid = _formKey.currentState?.validate() ?? false;
                  if (!valid) return;
                  Navigator.of(context).pop(
                    _RefundRequest(
                      amount: _customAmount
                          ? double.parse(_amountController.text.trim())
                          : null,
                      note: _noteController.text.trim().isEmpty
                          ? 'Merchant refund'
                          : _noteController.text.trim(),
                    ),
                  );
                },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
          child: const Text('Refund'),
        ),
      ],
    );
  }
}

class _RefundRequest {
  const _RefundRequest({required this.amount, required this.note});

  final double? amount;
  final String note;
}

class _InStoreCollectionRequest {
  const _InStoreCollectionRequest({
    required this.paymentMethod,
    required this.collectionReference,
  });

  final String paymentMethod;
  final String collectionReference;

  String get methodLabel => paymentMethod == 'pos_card' ? 'POS card' : 'cash';
}

class _InStoreCollectionDialog extends StatefulWidget {
  const _InStoreCollectionDialog({required this.order});

  final MerchantOrder order;

  @override
  State<_InStoreCollectionDialog> createState() =>
      _InStoreCollectionDialogState();
}

class _InStoreCollectionDialogState extends State<_InStoreCollectionDialog> {
  late String _paymentMethod;
  final _referenceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _paymentMethod = widget.order.inStoreCashEnabled ? 'cash' : 'pos_card';
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final hasAvailableMethod = order.hasAvailableInStoreCollectionMethod;

    return AlertDialog(
      title: const Text('Collect payment'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.displayId,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${order.currency} \$${order.totalAmount.toStringAsFixed(2)} · ${order.inStorePaymentLabel}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            if (!hasAvailableMethod)
              Text(
                'No in-store payment method is enabled for this order.',
                style: TextStyle(color: Colors.red.shade700),
              )
            else ...[
              if (order.inStoreCashEnabled)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'cash',
                  groupValue: _paymentMethod,
                  title: const Text('Cash'),
                  onChanged: (value) {
                    if (value != null) setState(() => _paymentMethod = value);
                  },
                ),
              if (order.inStorePosCardEnabled)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'pos_card',
                  groupValue: _paymentMethod,
                  title: const Text('POS card'),
                  onChanged: (value) {
                    if (value != null) setState(() => _paymentMethod = value);
                  },
                ),
              if (_paymentMethod == 'pos_card') ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _referenceController,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    labelText: 'POS reference (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: hasAvailableMethod
              ? () => Navigator.of(context).pop(
                  _InStoreCollectionRequest(
                    paymentMethod: _paymentMethod,
                    collectionReference: _referenceController.text.trim(),
                  ),
                )
              : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
      children: [
        Icon(icon, size: 48, color: Colors.grey.shade500),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
      ],
    );
  }
}

class _OrderAction {
  const _OrderAction(this.status, this.label);

  final String status;
  final String label;
}

_OrderAction? _primaryActionFor(MerchantOrder order) {
  switch (order.status) {
    case 'created':
      return order.isInStorePayment
          ? const _OrderAction('accepted', 'Accept')
          : null;
    case 'paid':
      return const _OrderAction('accepted', 'Accept');
    case 'accepted':
      return const _OrderAction('preparing', 'Start');
    case 'preparing':
      return const _OrderAction('ready', 'Ready');
    case 'ready':
      return order.isDelivery
          ? const _OrderAction('on_the_way', 'Dispatch')
          : const _OrderAction('completed', 'Complete');
    case 'on_the_way':
      return const _OrderAction('delivered', 'Delivered');
    default:
      return null;
  }
}

List<_OrderAction> _destructiveActionsFor(MerchantOrder order) {
  if (order.isPendingPayment ||
      (order.isInStorePayment &&
          order.isAwaitingInStoreCollection &&
          order.normalizedStatus == 'created')) {
    return const [_OrderAction('cancelled', 'Cancel')];
  }

  switch (order.normalizedStatus) {
    case 'paid':
    case 'accepted':
    case 'preparing':
    case 'ready':
    case 'on_the_way':
    case 'completed':
    case 'delivered':
    case 'partially_refunded':
      if (!order.canRefund) return const [];
      return const [_OrderAction('refunded', 'Refund')];
    default:
      return const [];
  }
}

Color _statusColor(String status, Color fallback) {
  switch (status) {
    case 'created':
    case 'pending':
    case 'pending_payment':
    case 'awaiting_collection':
      return Colors.orange.shade800;
    case 'cancelled':
    case 'partially_refunded':
    case 'refunded':
      return Colors.red.shade700;
    case 'ready':
    case 'on_the_way':
      return Colors.blue.shade700;
    case 'delivered':
    case 'completed':
      return Colors.green.shade700;
    default:
      return fallback;
  }
}

const _allStatusFilters = <_OrderFilter>[
  _OrderFilter('all', 'All'),
  _OrderFilter('pending_payment', 'Pending payment'),
  _OrderFilter('awaiting_collection', 'Awaiting collection'),
  _OrderFilter('paid', 'Paid'),
  _OrderFilter('accepted', 'Accepted'),
  _OrderFilter('preparing', 'Preparing'),
  _OrderFilter('ready', 'Ready'),
  _OrderFilter('on_the_way', 'On the way'),
  _OrderFilter('delivered', 'Delivered'),
  _OrderFilter('completed', 'Completed'),
  _OrderFilter('cancelled', 'Cancelled'),
  _OrderFilter('partially_refunded', 'Partially refunded'),
  _OrderFilter('refunded', 'Refunded'),
];

const _deliveryStatusFilters = <_OrderFilter>[
  _OrderFilter('all', 'All'),
  _OrderFilter('pending_payment', 'Pending payment'),
  _OrderFilter('paid', 'Paid'),
  _OrderFilter('accepted', 'Accepted'),
  _OrderFilter('preparing', 'Preparing'),
  _OrderFilter('ready', 'Ready'),
  _OrderFilter('on_the_way', 'On the way'),
  _OrderFilter('delivered', 'Delivered'),
  _OrderFilter('cancelled', 'Cancelled'),
  _OrderFilter('partially_refunded', 'Partially refunded'),
  _OrderFilter('refunded', 'Refunded'),
];

const _nonDeliveryStatusFilters = <_OrderFilter>[
  _OrderFilter('all', 'All'),
  _OrderFilter('pending_payment', 'Pending payment'),
  _OrderFilter('awaiting_collection', 'Awaiting collection'),
  _OrderFilter('paid', 'Paid'),
  _OrderFilter('accepted', 'Accepted'),
  _OrderFilter('preparing', 'Preparing'),
  _OrderFilter('ready', 'Ready'),
  _OrderFilter('completed', 'Completed'),
  _OrderFilter('cancelled', 'Cancelled'),
  _OrderFilter('partially_refunded', 'Partially refunded'),
  _OrderFilter('refunded', 'Refunded'),
];

List<_OrderFilter> _statusFiltersForFulfillment(String fulfillmentType) {
  return switch (fulfillmentType) {
    'delivery' => _deliveryStatusFilters,
    'takeout' || 'dine_in' => _nonDeliveryStatusFilters,
    _ => _allStatusFilters,
  };
}

bool _statusAllowedForFulfillment(String fulfillmentType, String status) {
  return _statusFiltersForFulfillment(
    fulfillmentType,
  ).any((filter) => filter.status == status);
}

bool _isFulfillmentFilter(String? value) {
  return _fulfillmentFilters.any((filter) => filter.type == value);
}

List<_BusinessFilter> _businessQueueFiltersForFulfillment(
  String fulfillmentType,
) {
  return fulfillmentType == 'delivery'
      ? _businessDeliveryQueueFilters
      : _businessNonDeliveryQueueFilters;
}

bool _businessQueueAllowedForFulfillment(String fulfillmentType, String queue) {
  return _businessQueueFiltersForFulfillment(
    fulfillmentType,
  ).any((filter) => filter.key == queue);
}

bool _isBusinessFulfillmentFilter(String? value) {
  return _businessFulfillmentFilters.any((filter) => filter.type == value);
}

bool _isBusinessStageFilter(String? value) {
  return _businessStageFilters.any((filter) => filter.key == value);
}

String _businessStageLabel(String stage) {
  for (final filter in _businessStageFilters) {
    if (filter.key == stage) return filter.label;
  }
  return 'Active';
}

DateTimeRange _todayDateRange() {
  final now = DateTime.now();
  return DateTimeRange(start: _startOfDay(now), end: _endOfDay(now));
}

DateTimeRange? _dateRangeForShortcut(_DateShortcut shortcut) {
  final days = shortcut.days;
  if (days == null) return null;

  final today = DateTime.now();
  final end = _endOfDay(today);
  final start = _startOfDay(today.subtract(Duration(days: days - 1)));
  return DateTimeRange(start: start, end: end);
}

_DateShortcut? _dateShortcutByKey(String key) {
  for (final shortcut in _dateShortcuts) {
    if (shortcut.key == key) return shortcut;
  }
  return null;
}

DateTimeRange _dateRangeForCustom(DateTimeRange picked) {
  return DateTimeRange(
    start: _startOfDay(picked.start),
    end: _endOfDay(picked.end),
  );
}

DateTime _startOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime _endOfDay(DateTime date) {
  return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _isTodayRange(DateTimeRange range) {
  final today = DateTime.now();
  return _isSameDay(range.start, today) && _isSameDay(range.end, today);
}

_DateShortcut? _shortcutForRange(DateTimeRange? range) {
  if (range == null) return _dateShortcuts.first;

  for (final shortcut in _dateShortcuts) {
    if (shortcut.days == null) continue;
    final shortcutRange = _dateRangeForShortcut(shortcut);
    if (shortcutRange == null) continue;
    if (_isSameDay(range.start, shortcutRange.start) &&
        _isSameDay(range.end, shortcutRange.end)) {
      return shortcut;
    }
  }

  return null;
}

String _dateRangeLabel(DateTimeRange? range) {
  if (range == null) return 'All dates';

  final startLabel = _formatDate(range.start);
  if (_isSameDay(range.start, range.end)) {
    return _isTodayRange(range) ? 'Today - $startLabel' : startLabel;
  }
  return '$startLabel - ${_formatDate(range.end)}';
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _humanize(String value) {
  return value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) {
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String? _refundAmountValidator(String? value, double maxAmount) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a valid amount';
  if (parsed <= 0) return 'Amount must be greater than 0';
  if (parsed > maxAmount) {
    return 'Must be at most ${maxAmount.toStringAsFixed(2)}';
  }
  return null;
}
