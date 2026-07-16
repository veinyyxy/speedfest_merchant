import 'package:flutter/material.dart';

import '../Models/merchant_order.dart';

typedef SyncPaymentRecordsCallback =
    Future<MerchantOrder?> Function(MerchantOrder order);
typedef PrintOrderCallback = Future<void> Function(MerchantOrder order);

class MerchantOrderDetailSheet extends StatefulWidget {
  const MerchantOrderDetailSheet({
    super.key,
    required this.order,
    this.onSyncPaymentRecords,
    this.onPrintOrder,
  });

  final MerchantOrder order;
  final SyncPaymentRecordsCallback? onSyncPaymentRecords;
  final PrintOrderCallback? onPrintOrder;

  @override
  State<MerchantOrderDetailSheet> createState() =>
      _MerchantOrderDetailSheetState();
}

class _MerchantOrderDetailSheetState extends State<MerchantOrderDetailSheet> {
  late MerchantOrder _order;
  bool _isSyncingPaymentRecords = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _syncPaymentRecords() async {
    final callback = widget.onSyncPaymentRecords;
    if (callback == null || _isSyncingPaymentRecords) return;

    setState(() => _isSyncingPaymentRecords = true);
    final syncedOrder = await callback(_order);
    if (!mounted) return;
    setState(() {
      if (syncedOrder != null) _order = syncedOrder;
      _isSyncingPaymentRecords = false;
    });
  }

  Future<void> _printOrder() async {
    final callback = widget.onPrintOrder;
    if (callback == null || _isPrinting) return;

    setState(() => _isPrinting = true);
    await callback(_order);
    if (!mounted) return;
    setState(() => _isPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomPadding),
        child: ListView(
          shrinkWrap: true,
          children: [
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
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    order.displayId,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Print order',
                  onPressed: widget.onPrintOrder == null || _isPrinting
                      ? null
                      : _printOrder,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                ),
                const SizedBox(width: 4),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 18),
            _DetailRow(label: 'Created', value: order.createdAtLabel),
            _DetailRow(label: 'Fulfillment', value: order.fulfillmentLabel),
            _PaymentDetailRow(
              value: order.paymentDetailStatusLabel,
              isSyncing: _isSyncingPaymentRecords,
              onSync: widget.onSyncPaymentRecords == null
                  ? null
                  : _syncPaymentRecords,
            ),
            if (order.isInStorePayment) ...[
              _DetailRow(
                label: 'Payment route',
                value: order.inStorePaymentLabel,
              ),
              _DetailRow(
                label: 'Collect when',
                value: order.collectionTimingLabel,
              ),
              if (order.paymentMethodLabel.isNotEmpty)
                _DetailRow(label: 'Method', value: order.paymentMethodLabel),
            ],
            _DetailRow(label: 'Customer', value: order.customerName),
            _DetailRow(label: 'Phone', value: order.customerPhone),
            _DetailRow(label: 'Email', value: order.customerEmail),
            _DetailRow(label: 'Address', value: order.shippingAddress),
            _DetailRow(label: 'Table', value: order.tableNumber),
            _DetailRow(label: 'Pickup', value: order.pickupLocation),
            _DetailRow(label: 'Note', value: order.deliveryNote),
            if (order.isReviewed) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.grey.shade200),
              const SizedBox(height: 12),
              _OrderReviewSection(order: order),
            ],
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),
            Text(
              'Items',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (order.items.isEmpty)
              Text(
                'No item details available.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              ...order.items.map((item) => _ItemLine(item: item)),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),
            _MoneyRow(label: 'Subtotal', value: order.pricing.subtotal),
            _MoneyRow(label: 'Delivery fee', value: order.pricing.deliveryFee),
            _MoneyRow(
              label: 'Service fee',
              value: order.pricing.deliveryServiceFee,
            ),
            _MoneyRow(label: 'Taxes', value: order.pricing.taxes),
            _MoneyRow(label: 'Tip', value: order.pricing.tipAmount),
            if (order.refundedAmount > 0)
              _MoneyRow(label: 'Refunded', value: order.refundedAmount),
            _MoneyRow(label: 'Total', value: order.totalAmount, isTotal: true),
          ],
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item});

  final MerchantOrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${item.quantity}x ${item.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.isRewardItem)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Reward',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text('CAD \$${item.price.toStringAsFixed(2)}'),
            ],
          ),
          if (item.optionGroups.isNotEmpty) ...[
            const SizedBox(height: 3),
            ...item.optionGroups.entries.map(
              (entry) =>
                  _OptionGroupLines(groupName: entry.key, options: entry.value),
            ),
          ],
          if (item.reviewRating > 0) ...[
            const SizedBox(height: 5),
            _ReadOnlyStarRating(rating: item.reviewRating),
          ],
          if (item.specialInstructions.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Note: ${item.specialInstructions}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionGroupLines extends StatelessWidget {
  const _OptionGroupLines({required this.groupName, required this.options});

  final String groupName;
  final List<MerchantOrderItemOption> options;

  @override
  Widget build(BuildContext context) {
    final color = Colors.grey.shade700;
    final displayGroupName = groupName.trim().isEmpty ? 'Options' : groupName;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '-$displayGroupName:',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          ...options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(left: 14, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${option.quantity}x ${option.name}',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    option.totalPrice == 0
                        ? 'Included'
                        : 'CAD \$${option.totalPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderReviewSection extends StatelessWidget {
  const _OrderReviewSection({required this.order});

  final MerchantOrder order;

  @override
  Widget build(BuildContext context) {
    final review = order.review;
    if (review == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Customer review',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (review.hasComment)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(review.comment),
          )
        else
          Text(
            'No overall note. Product ratings are shown with the items below.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        if (review.createdAtLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Reviewed ${review.createdAtLabel}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _ReadOnlyStarRating extends StatelessWidget {
  const _ReadOnlyStarRating({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final clampedRating = rating.clamp(0, 5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index += 1)
          Icon(
            index <= clampedRating
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            size: 16,
            color: index <= clampedRating
                ? Colors.amber.shade700
                : Colors.grey.shade400,
          ),
        const SizedBox(width: 6),
        Text(
          '$clampedRating/5',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PaymentDetailRow extends StatelessWidget {
  const _PaymentDetailRow({
    required this.value,
    required this.isSyncing,
    required this.onSync,
  });

  final String value;
  final bool isSyncing;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              'Payment',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (onSync != null)
                  OutlinedButton.icon(
                    onPressed: isSyncing ? null : onSync,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: isSyncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_outlined, size: 16),
                    label: Text(isSyncing ? 'Syncing records' : 'Sync records'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final double value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    if (!isTotal && value == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            'CAD \$${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
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

Color _statusColor(String status, Color fallback) {
  switch (status) {
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
