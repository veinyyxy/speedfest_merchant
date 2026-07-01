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
  String _fulfillmentFilter = 'all';
  String _statusFilter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchOrders());
  }

  Future<void> _fetchOrders() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantOrdersProvider>().fetchOrders(
      apiClient: session.apiClient,
      token: token,
    );
  }

  List<MerchantOrder> _filteredOrders(List<MerchantOrder> orders) {
    return orders
        .where(
          (order) =>
              _matchesFulfillmentFilter(order) && _matchesStatusFilter(order),
        )
        .toList(growable: false);
  }

  bool _matchesFulfillmentFilter(MerchantOrder order) {
    if (_fulfillmentFilter == 'all') return true;
    return order.normalizedFulfillmentType == _fulfillmentFilter;
  }

  bool _matchesStatusFilter(MerchantOrder order) {
    if (_statusFilter == 'all') return true;

    if (_statusFilter == 'pending_payment') {
      return order.isPendingPayment;
    }

    return order.normalizedStatus == _statusFilter;
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
    final orders = _filteredOrders(provider.orders);
    final statusFilters = _statusFiltersForFulfillment(_fulfillmentFilter);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
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
          _FulfillmentFilterBar(
            selectedType: _fulfillmentFilter,
            onSelected: (type) {
              setState(() {
                _fulfillmentFilter = type;
                if (!_statusAllowedForFulfillment(type, _statusFilter)) {
                  _statusFilter = 'all';
                }
              });
            },
          ),
          _StatusFilterBar(
            filters: statusFilters,
            selectedStatus: _statusFilter,
            onSelected: (status) {
              setState(() => _statusFilter = status);
            },
          ),
          Expanded(
            child: _OrdersBody(
              provider: provider,
              orders: orders,
              onRefresh: _fetchOrders,
              onOpenDetail: _showDetail,
              onUpdateStatus: _updateStatus,
              onRefund: _refundOrder,
            ),
          ),
        ],
      ),
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

  static const filters = <_FulfillmentFilter>[
    _FulfillmentFilter('all', 'All'),
    _FulfillmentFilter('delivery', 'Delivery'),
    _FulfillmentFilter('takeout', 'Takeout'),
    _FulfillmentFilter('dine_in', 'Dine-in'),
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
            selected: selectedType == filter.type,
            onSelected: (_) => onSelected(filter.type),
          );
        },
      ),
    );
  }
}

class _FulfillmentFilter {
  const _FulfillmentFilter(this.type, this.label);

  final String type;
  final String label;
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

  final String status;
  final String label;
}

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({
    required this.provider,
    required this.orders,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onUpdateStatus,
    required this.onRefund,
  });

  final MerchantOrdersProvider provider;
  final List<MerchantOrder> orders;
  final Future<void> Function() onRefresh;
  final ValueChanged<MerchantOrder> onOpenDetail;
  final void Function(MerchantOrder order, String status) onUpdateStatus;
  final ValueChanged<MerchantOrder> onRefund;

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

    if (orders.isEmpty) {
      return _StateMessage(
        icon: Icons.filter_list_off_outlined,
        title: 'No matching orders',
        message: 'Try another order type or status filter.',
        onPressed: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return _OrderCard(
            order: order,
            isUpdating: provider.isUpdating,
            onOpenDetail: () => onOpenDetail(order),
            onUpdateStatus: (status) => onUpdateStatus(order, status),
            onRefund: () => onRefund(order),
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
    required this.onRefund,
  });

  final MerchantOrder order;
  final bool isUpdating;
  final VoidCallback onOpenDetail;
  final ValueChanged<String> onUpdateStatus;
  final VoidCallback onRefund;

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
                if (order.paymentStatusLabel.isNotEmpty)
                  _InfoPill(
                    icon: Icons.credit_card_outlined,
                    label: 'Payment: ${order.paymentStatusLabel}',
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
      order.isPendingPayment ? 'pending_payment' : order.status,
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
  if (order.isPendingPayment) {
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
