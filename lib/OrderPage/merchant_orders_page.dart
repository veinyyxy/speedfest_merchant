import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOrders());
  }

  Future<void> _fetchOrders([String? status]) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantOrdersProvider>().fetchOrders(
      apiClient: session.apiClient,
      token: token,
      status: status,
    );
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
      await _fetchOrders(ordersProvider.selectedStatus);
    }
  }

  Future<void> _showDetail(MerchantOrder order) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final detail = await context
        .read<MerchantOrdersProvider>()
        .fetchOrderDetail(
          apiClient: session.apiClient,
          token: token,
          orderId: order.id,
        );
    if (!mounted || detail == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => MerchantOrderDetailSheet(order: detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantOrdersProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading
                ? null
                : () => _fetchOrders(provider.selectedStatus),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusFilterBar(
            selectedStatus: provider.selectedStatus,
            onSelected: _fetchOrders,
          ),
          Expanded(
            child: _OrdersBody(
              provider: provider,
              onRefresh: () => _fetchOrders(provider.selectedStatus),
              onOpenDetail: _showDetail,
              onUpdateStatus: _updateStatus,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.selectedStatus,
    required this.onSelected,
  });

  final String? selectedStatus;
  final ValueChanged<String?> onSelected;

  static const filters = <_OrderFilter>[
    _OrderFilter(null, 'All'),
    _OrderFilter('paid', 'Paid'),
    _OrderFilter('accepted', 'Accepted'),
    _OrderFilter('preparing', 'Preparing'),
    _OrderFilter('ready', 'Ready'),
    _OrderFilter('on_the_way', 'On the way'),
    _OrderFilter('completed', 'Completed'),
    _OrderFilter('cancelled', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          return ChoiceChip(
            label: Text(filter.label),
            selected: selectedStatus == filter.status,
            onSelected: (_) => onSelected(filter.status),
          );
        },
      ),
    );
  }
}

class _OrderFilter {
  const _OrderFilter(this.status, this.label);

  final String? status;
  final String label;
}

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({
    required this.provider,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onUpdateStatus,
  });

  final MerchantOrdersProvider provider;
  final Future<void> Function() onRefresh;
  final ValueChanged<MerchantOrder> onOpenDetail;
  final void Function(MerchantOrder order, String status) onUpdateStatus;

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
        message: 'New customer orders will appear in this workspace.',
        onPressed: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: provider.orders.length,
        itemBuilder: (context, index) {
          final order = provider.orders[index];
          return _OrderCard(
            order: order,
            isUpdating: provider.isUpdating,
            onOpenDetail: () => onOpenDetail(order),
            onUpdateStatus: (status) => onUpdateStatus(order, status),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isUpdating,
    required this.onOpenDetail,
    required this.onUpdateStatus,
  });

  final MerchantOrder order;
  final bool isUpdating;
  final VoidCallback onOpenDetail;
  final ValueChanged<String> onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final nextAction = _primaryActionFor(order);
    final destructiveActions = _destructiveActionsFor(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                _StatusChip(status: order.status),
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
                if (order.paymentStatusLabel.isNotEmpty)
                  _InfoPill(
                    icon: Icons.credit_card_outlined,
                    label: order.paymentStatusLabel,
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
                for (final action in destructiveActions) ...[
                  TextButton(
                    onPressed: isUpdating
                        ? null
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
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status, Theme.of(context).colorScheme.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _humanize(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
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
  switch (order.status) {
    case 'paid':
    case 'accepted':
    case 'preparing':
      return const [_OrderAction('cancelled', 'Cancel')];
    case 'ready':
    case 'completed':
    case 'delivered':
      return const [_OrderAction('refunded', 'Refund')];
    default:
      return const [];
  }
}

Color _statusColor(String status, Color fallback) {
  switch (status) {
    case 'cancelled':
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
