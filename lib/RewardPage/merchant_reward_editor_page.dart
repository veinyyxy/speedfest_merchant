import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Controller/merchant_products_provider.dart';
import '../Controller/merchant_rewards_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_product.dart';
import '../Models/merchant_reward.dart';

class MerchantRewardEditorPage extends StatefulWidget {
  const MerchantRewardEditorPage({super.key, this.reward});

  final MerchantReward? reward;

  @override
  State<MerchantRewardEditorPage> createState() =>
      _MerchantRewardEditorPageState();
}

class _MerchantRewardEditorPageState extends State<MerchantRewardEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pointsController = TextEditingController();
  final _discountController = TextEditingController();
  final _expiresController = TextEditingController();
  final _sortOrderController = TextEditingController();

  bool _loadedProducts = false;
  bool _active = true;
  String _rewardType = 'discount';
  String? _productId;
  bool get _isEditing => widget.reward != null;

  @override
  void initState() {
    super.initState();
    final reward = widget.reward;
    if (reward == null) {
      _expiresController.text = '30';
      _sortOrderController.text = '0';
      return;
    }

    _titleController.text = reward.title;
    _descriptionController.text = reward.description;
    _pointsController.text = reward.pointsCost.toString();
    _discountController.text = reward.discountAmount.toStringAsFixed(2);
    _expiresController.text = reward.expiresInDays.toString();
    _sortOrderController.text = reward.sortOrder.toString();
    _rewardType = reward.rewardType == 'product' ? 'product' : 'discount';
    _productId = reward.productId.isEmpty ? null : reward.productId;
    _active = reward.active;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedProducts) return;
    _loadedProducts = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _pointsController.dispose();
    _discountController.dispose();
    _expiresController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantProductsProvider>().fetchProducts(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final provider = context.read<MerchantRewardsProvider>();
    final reward = MerchantReward(
      id: widget.reward?.id ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      pointsCost: _readInt(_pointsController.text),
      discountAmount: _rewardType == 'discount'
          ? _readDouble(_discountController.text)
          : 0,
      expiresInDays: _readInt(_expiresController.text),
      active: _active,
      sortOrder: _readOptionalInt(_sortOrderController.text),
      rewardType: _rewardType,
      currency: 'CAD',
      productId: _rewardType == 'product' ? _productId ?? '' : '',
    );

    final ok = _isEditing
        ? await provider.updateReward(
            apiClient: session.apiClient,
            token: token,
            reward: reward,
          )
        : await provider.createReward(
            apiClient: session.apiClient,
            token: token,
            reward: reward,
          );
    if (!mounted) return;

    if (ok) {
      _showMessage(_isEditing ? 'Reward updated.' : 'Reward created.');
      Navigator.of(context).pop(true);
      return;
    }

    _showMessage(
      provider.errorMessage ??
          (_isEditing
              ? 'Reward could not be updated.'
              : 'Reward could not be created.'),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantRewardsProvider>();
    final productsProvider = context.watch<MerchantProductsProvider>();
    final products = _rewardProducts(productsProvider.products);
    final selectedProductId =
        products.any((product) => product.id == _productId) ? _productId : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit reward' : 'Add reward'),
        actions: [
          TextButton.icon(
            onPressed: provider.isSaving ? null : _save,
            icon: provider.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _SectionCard(
              title: 'Reward details',
              children: [
                TextFormField(
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Reward title',
                    hintText: 'CA\$3 Off Reward',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'discount',
                      icon: Icon(Icons.local_offer_outlined),
                      label: Text('Amount off'),
                    ),
                    ButtonSegment(
                      value: 'product',
                      icon: Icon(Icons.restaurant_menu_outlined),
                      label: Text('Product'),
                    ),
                  ],
                  selected: {_rewardType},
                  onSelectionChanged: (selection) {
                    final value = selection.first;
                    setState(() {
                      _rewardType = value;
                      if (value == 'discount') {
                        _productId = null;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Redeem rule',
              children: [
                _ResponsivePair(
                  first: TextFormField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Points cost',
                      suffixText: 'pts',
                      border: OutlineInputBorder(),
                    ),
                    validator: _positiveIntValidator,
                  ),
                  second: _rewardType == 'discount'
                      ? TextFormField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Discount amount',
                            prefixText: 'CAD \$',
                            border: OutlineInputBorder(),
                          ),
                          validator: _positiveMoneyValidator,
                        )
                      : const _ProductRewardValueHint(),
                ),
                if (_rewardType == 'product') ...[
                  const SizedBox(height: 12),
                  if (productsProvider.isLoading && products.isEmpty) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    value: selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Reward product',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final product in products)
                        DropdownMenuItem(
                          value: product.id,
                          child: Text(_productLabel(product)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _productId = value),
                    validator: _productValidator,
                  ),
                  if (productsProvider.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      productsProvider.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _ResponsivePair(
                  first: TextFormField(
                    controller: _expiresController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Expires after',
                      suffixText: 'days',
                      border: OutlineInputBorder(),
                    ),
                    validator: _expiresValidator,
                  ),
                  second: TextFormField(
                    controller: _sortOrderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sort order',
                      hintText: '0',
                      border: OutlineInputBorder(),
                    ),
                    validator: _optionalIntegerValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Availability',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Active rewards are shown to customers for future redemption.',
                  ),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: provider.isSaving ? null : _save,
          icon: provider.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_isEditing ? 'Save changes' : 'Create reward'),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _ProductRewardValueHint extends StatelessWidget {
  const _ProductRewardValueHint();

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Reward value',
        border: OutlineInputBorder(),
      ),
      child: Text(
        'The selected product will be added to the order for free.',
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}

List<MerchantProduct> _rewardProducts(List<MerchantProduct> products) {
  return products
      .where((product) => product.id.isNotEmpty && product.status != 'archived')
      .toList(growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

String _productLabel(MerchantProduct product) {
  final price = 'CAD \$${product.basePrice.toStringAsFixed(2)}';
  final status = product.status == 'active' ? '' : ' • ${product.statusLabel}';
  return '${product.name} • $price$status';
}

String? _requiredValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'This field is required';
  }
  return null;
}

String? _positiveIntValidator(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed <= 0) {
    return 'Enter a number greater than 0';
  }
  return null;
}

String? _productValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Choose a product reward';
  }
  return null;
}

String? _positiveMoneyValidator(String? value) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed <= 0) {
    return 'Enter an amount greater than 0';
  }
  return null;
}

String? _expiresValidator(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 1) {
    return 'Enter at least 1 day';
  }
  return null;
}

String? _optionalIntegerValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  return int.tryParse(text) == null ? 'Enter a whole number' : null;
}

int _readInt(String value) => int.tryParse(value.trim()) ?? 0;

int _readOptionalInt(String value) {
  final text = value.trim();
  if (text.isEmpty) return 0;
  return int.tryParse(text) ?? 0;
}

double _readDouble(String value) => double.tryParse(value.trim()) ?? 0;
