import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Controller/merchant_products_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_category.dart';
import '../Models/merchant_option_group.dart';
import '../Models/merchant_product.dart';
import '../Models/merchant_product_create_request.dart';

class MerchantProductEditorPage extends StatefulWidget {
  const MerchantProductEditorPage({super.key, this.product});

  final MerchantProduct? product;

  @override
  State<MerchantProductEditorPage> createState() =>
      _MerchantProductEditorPageState();
}

class _MerchantProductEditorPageState extends State<MerchantProductEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final List<_OptionGroupForm> _optionGroups = [];

  bool _loadedEditorData = false;
  bool _visibleInMenu = true;
  String _status = 'active';
  int? _categoryId;
  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product == null) return;

    _skuController.text = product.sku;
    _nameController.text = product.name;
    _descriptionController.text = product.description;
    _priceController.text = product.basePrice.toStringAsFixed(2);
    _imageUrlController.text = product.imageUrl;
    _status = product.status;
    _visibleInMenu = product.visibleInMenu;
    if (product.categoryIds.isNotEmpty) {
      _categoryId = product.categoryIds.first;
    }
    _optionGroups.addAll(
      product.optionGroups.map(_OptionGroupForm.existingGroup),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedEditorData) return;
    _loadedEditorData = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEditorData());
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _imageUrlController.dispose();
    for (final group in _optionGroups) {
      group.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEditorData() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final provider = context.read<MerchantProductsProvider>();
    await provider.fetchCategories(apiClient: session.apiClient, token: token);
    await provider.fetchProducts(apiClient: session.apiClient, token: token);
    await provider.fetchOptionGroups(
      apiClient: session.apiClient,
      token: token,
    );
    if (!mounted ||
        _isEditing ||
        _categoryId != null ||
        provider.categories.isEmpty) {
      return;
    }
    setState(() => _categoryId = provider.categories.first.id);
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;

    if (_categoryId == null && (!_isEditing || _visibleInMenu)) {
      _showMessage('Choose a category before saving.');
      return;
    }

    final optionError = _validateOptionGroups(_optionGroups);
    if (optionError != null) {
      _showMessage(optionError);
      return;
    }

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantProductsProvider>();
    final categoryIds = _categoryId == null ? <int>[] : [_categoryId!];

    final request = MerchantProductCreateRequest(
      productId: widget.product?.id ?? '',
      sku: _skuController.text.trim(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      basePrice: _readDouble(_priceController.text),
      status: _status,
      visibleInMenu: _visibleInMenu,
      categoryIds: categoryIds,
      imageUrl: _imageUrlController.text.trim(),
      optionGroups: [
        for (var i = 0; i < _optionGroups.length; i++)
          _optionGroups[i].toDraft(i, provider.optionGroups),
      ],
    );

    final ok = _isEditing
        ? await provider.updateProduct(
            apiClient: session.apiClient,
            token: token,
            request: request,
          )
        : await provider.createProduct(
            apiClient: session.apiClient,
            token: token,
            request: request,
          );
    if (!mounted) return;

    if (ok) {
      _showMessage(_isEditing ? 'Product updated.' : 'Product created.');
      Navigator.of(context).pop(true);
      return;
    }

    _showMessage(
      provider.errorMessage ??
          (_isEditing
              ? 'Product could not be updated.'
              : 'Product could not be created.'),
    );
  }

  void _addOptionGroup() {
    setState(() => _optionGroups.add(_OptionGroupForm()));
  }

  Future<void> _openCreateCategoryDialog() async {
    final categories = context.read<MerchantProductsProvider>().categories;
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (context) => _CreateCategoryDialog(categories: categories),
    );
    if (result == null) return;
    if (!mounted) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantProductsProvider>();

    final created = await provider.createCategory(
      apiClient: session.apiClient,
      token: token,
      name: result.name,
      parentId: result.parentId,
    );
    if (!mounted) return;

    if (created == null) {
      _showMessage(provider.errorMessage ?? 'Category could not be created.');
      return;
    }

    setState(() => _categoryId = created.id);
    _showMessage('Category created.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantProductsProvider>();
    final categories = provider.categories;
    final existingProducts = provider.products;
    final existingOptionGroups = provider.optionGroups;
    final selectedCategoryId =
        categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit product' : 'Add product'),
        actions: [
          TextButton.icon(
            onPressed: provider.isCreating ? null : _save,
            icon: provider.isCreating
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
              title: 'Basic info',
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skuController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SKU',
                    hintText: 'Leave empty to auto-generate',
                    border: OutlineInputBorder(),
                  ),
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
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Base price',
                          prefixText: 'CAD \$',
                          border: OutlineInputBorder(),
                        ),
                        validator: _moneyValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('Archived'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _status = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Category and image',
              children: [
                if (provider.isLoadingCategories && categories.isEmpty) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                if (categories.isEmpty && !provider.isLoadingCategories)
                  OutlinedButton.icon(
                    onPressed: _loadEditorData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Load categories'),
                  )
                else
                  DropdownButtonFormField<int>(
                    value: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(_categoryLabel(category, categories)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                    validator: (value) {
                      if (value == null && (!_isEditing || _visibleInMenu)) {
                        return 'Category is required';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: provider.isLoadingCategories
                        ? null
                        : _openCreateCategoryDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New category'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _imageUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show in buyer menu'),
                  subtitle: const Text(
                    'Turn off when this product should only be reused as an option.',
                  ),
                  value: _visibleInMenu,
                  onChanged: (value) => setState(() => _visibleInMenu = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OptionsSection(
              groups: _optionGroups,
              existingProducts: existingProducts,
              existingOptionGroups: existingOptionGroups,
              onAddGroup: _addOptionGroup,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: provider.isCreating ? null : _save,
          icon: provider.isCreating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_isEditing ? 'Save changes' : 'Create product'),
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

class _CreateCategoryDialog extends StatefulWidget {
  const _CreateCategoryDialog({required this.categories});

  final List<MerchantCategory> categories;

  @override
  State<_CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<_CreateCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _parentId = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _CategoryFormResult(
        name: _nameController.text.trim(),
        parentId: _parentId == 0 ? null : _parentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Category name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: _requiredValidator,
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _parentId,
                decoration: const InputDecoration(
                  labelText: 'Parent category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('No parent')),
                  for (final category in widget.categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(_categoryLabel(category, widget.categories)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _parentId = value);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _OptionsSection extends StatelessWidget {
  const _OptionsSection({
    required this.groups,
    required this.existingProducts,
    required this.existingOptionGroups,
    required this.onAddGroup,
    required this.onChanged,
  });

  final List<_OptionGroupForm> groups;
  final List<MerchantProduct> existingProducts;
  final List<MerchantOptionGroup> existingOptionGroups;
  final VoidCallback onAddGroup;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Options',
      children: [
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No option groups yet.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        for (var i = 0; i < groups.length; i++) ...[
          _OptionGroupEditor(
            group: groups[i],
            index: i,
            depth: 0,
            existingProducts: existingProducts,
            existingOptionGroups: existingOptionGroups,
            onChanged: onChanged,
            onRemove: () {
              groups.removeAt(i).dispose();
              onChanged();
            },
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: onAddGroup,
          icon: const Icon(Icons.add),
          label: const Text('Add option group'),
        ),
      ],
    );
  }
}

class _OptionGroupEditor extends StatelessWidget {
  const _OptionGroupEditor({
    required this.group,
    required this.index,
    required this.depth,
    required this.existingProducts,
    required this.existingOptionGroups,
    required this.onChanged,
    required this.onRemove,
  });

  final _OptionGroupForm group;
  final int index;
  final int depth;
  final List<MerchantProduct> existingProducts;
  final List<MerchantOptionGroup> existingOptionGroups;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: depth == 0 ? Colors.white : colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  depth == 0
                      ? 'Option group ${index + 1}'
                      : 'Child group ${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Remove group',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('New group')),
              ButtonSegment(value: true, label: Text('Existing group')),
            ],
            selected: {group.useExistingGroup},
            onSelectionChanged: (selection) {
              group.useExistingGroup = selection.first;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          if (group.useExistingGroup) ...[
            DropdownButtonFormField<String>(
              value: group.existingOptionGroupId,
              decoration: const InputDecoration(
                labelText: 'Option group',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final optionGroup in existingOptionGroups)
                  DropdownMenuItem(
                    value: optionGroup.id,
                    child: Text(
                      '${optionGroup.name} · ${optionGroup.summary}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                group.existingOptionGroupId = value;
                onChanged();
              },
              validator: (value) {
                if (!group.useExistingGroup) return null;
                return value == null ? 'Choose an existing group' : null;
              },
            ),
            const SizedBox(height: 12),
            _ExistingGroupSummary(
              optionGroup: _findOptionGroup(
                existingOptionGroups,
                group.existingOptionGroupId,
              ),
            ),
          ] else ...[
            TextFormField(
              controller: group.nameController,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('Single')),
                    ButtonSegment(value: 'multiple', label: Text('Multiple')),
                  ],
                  selected: {group.selectionType},
                  onSelectionChanged: (selection) {
                    group.selectionType = selection.first;
                    if (group.selectionType == 'single') {
                      group.maxSelectController.text = '1';
                    }
                    onChanged();
                  },
                ),
                FilterChip(
                  label: const Text('Required'),
                  selected: group.isRequired,
                  onSelected: (value) {
                    group.isRequired = value;
                    onChanged();
                  },
                ),
              ],
            ),
            if (group.selectionType == 'multiple') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: group.maxSelectController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max choices',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final max = int.tryParse(value?.trim() ?? '');
                  if (max == null || max < 1) return 'Enter a number above 0';
                  if (group.isRequired && max < 1) return 'Max must allow one';
                  return null;
                },
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Options',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    group.options.add(_OptionForm());
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ],
            ),
            if (group.options.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'This group needs at least one option.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            for (var i = 0; i < group.options.length; i++) ...[
              _OptionEditor(
                option: group.options[i],
                index: i,
                depth: depth,
                existingProducts: existingProducts,
                existingOptionGroups: existingOptionGroups,
                onChanged: onChanged,
                onRemove: () {
                  group.options.removeAt(i).dispose();
                  onChanged();
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _ExistingGroupSummary extends StatelessWidget {
  const _ExistingGroupSummary({required this.optionGroup});

  final MerchantOptionGroup? optionGroup;

  @override
  Widget build(BuildContext context) {
    if (optionGroup == null) {
      return Text(
        'Choose a saved group to reuse its options.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }

    final options = optionGroup!.options
        .take(4)
        .map((option) {
          final price = option.basePrice == 0
              ? ''
              : ' +\$${option.basePrice.toStringAsFixed(2)}';
          return '${option.name}$price';
        })
        .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        options.isEmpty
            ? optionGroup!.summary
            : '${optionGroup!.summary}: $options',
        style: TextStyle(color: Colors.grey.shade800),
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.option,
    required this.index,
    required this.depth,
    required this.existingProducts,
    required this.existingOptionGroups,
    required this.onChanged,
    required this.onRemove,
  });

  final _OptionForm option;
  final int index;
  final int depth;
  final List<MerchantProduct> existingProducts;
  final List<MerchantOptionGroup> existingOptionGroups;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final title = _optionTitle(option, existingProducts, index);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 12, right: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          option.useExistingProduct
              ? 'Existing product'
              : option.isActive
              ? 'Active'
              : 'Inactive',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: option.isActive,
              onChanged: option.useExistingProduct
                  ? null
                  : (value) {
                      option.isActive = value;
                      onChanged();
                    },
            ),
            IconButton(
              tooltip: 'Remove option',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('New product')),
              ButtonSegment(value: true, label: Text('Existing product')),
            ],
            selected: {option.useExistingProduct},
            onSelectionChanged: (selection) {
              option.useExistingProduct = selection.first;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          if (option.useExistingProduct) ...[
            DropdownButtonFormField<String>(
              value: option.existingProductId,
              decoration: const InputDecoration(
                labelText: 'Product',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final product in existingProducts)
                  DropdownMenuItem(
                    value: product.id,
                    child: Text(
                      '${product.name} · CAD \$${product.basePrice.toStringAsFixed(2)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                option.existingProductId = value;
                onChanged();
              },
              validator: (value) {
                if (!option.useExistingProduct) return null;
                return value == null ? 'Choose an existing product' : null;
              },
            ),
            const SizedBox(height: 12),
          ] else ...[
            TextFormField(
              controller: option.nameController,
              decoration: const InputDecoration(
                labelText: 'Option name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: option.skuController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Option SKU',
                hintText: 'Leave empty to auto-generate',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: option.priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Extra price',
                prefixText: 'CAD \$',
                border: OutlineInputBorder(),
              ),
              validator: _moneyValidator,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: option.descriptionController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: option.imageUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show in buyer menu'),
              subtitle: const Text(
                'Use the parent product category by default.',
              ),
              value: option.visibleInMenu,
              onChanged: (value) {
                option.visibleInMenu = value;
                onChanged();
              },
            ),
          ],
          const SizedBox(height: 12),
          _ChildGroupsEditor(
            groups: option.childGroups,
            depth: depth + 1,
            existingProducts: existingProducts,
            existingOptionGroups: existingOptionGroups,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ChildGroupsEditor extends StatelessWidget {
  const _ChildGroupsEditor({
    required this.groups,
    required this.depth,
    required this.existingProducts,
    required this.existingOptionGroups,
    required this.onChanged,
  });

  final List<_OptionGroupForm> groups;
  final int depth;
  final List<MerchantProduct> existingProducts;
  final List<MerchantOptionGroup> existingOptionGroups;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Child option groups',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                groups.add(_OptionGroupForm());
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add child group'),
            ),
          ],
        ),
        for (var i = 0; i < groups.length; i++) ...[
          _OptionGroupEditor(
            group: groups[i],
            index: i,
            depth: depth,
            existingProducts: existingProducts,
            existingOptionGroups: existingOptionGroups,
            onChanged: onChanged,
            onRemove: () {
              groups.removeAt(i).dispose();
              onChanged();
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CategoryFormResult {
  const _CategoryFormResult({required this.name, required this.parentId});

  final String name;
  final int? parentId;
}

class _OptionGroupForm {
  _OptionGroupForm();

  _OptionGroupForm.existingGroup(MerchantOptionGroup optionGroup) {
    useExistingGroup = true;
    existingOptionGroupId = optionGroup.id;
  }

  final TextEditingController nameController = TextEditingController();
  final TextEditingController maxSelectController = TextEditingController(
    text: '1',
  );
  final List<_OptionForm> options = [];

  bool useExistingGroup = false;
  String? existingOptionGroupId;
  String selectionType = 'single';
  bool isRequired = false;

  MerchantOptionGroupDraft toDraft(
    int index,
    List<MerchantOptionGroup> existingOptionGroups,
  ) {
    if (useExistingGroup) {
      final selected = _findOptionGroup(
        existingOptionGroups,
        existingOptionGroupId,
      );
      return MerchantOptionGroupDraft(
        optionGroupId: existingOptionGroupId ?? '',
        groupName: selected?.name ?? '',
        selectionType: selected?.selectionType ?? 'single',
        minSelect: selected?.minSelect ?? 0,
        maxSelect: selected?.maxSelect ?? 1,
        sortOrder: (index + 1) * 10,
        options: const [],
      );
    }

    final minSelect = isRequired ? 1 : 0;
    final maxSelect = selectionType == 'single'
        ? 1
        : _readPositiveInt(maxSelectController.text, options.length);

    return MerchantOptionGroupDraft(
      optionGroupId: '',
      groupName: nameController.text.trim(),
      selectionType: selectionType,
      minSelect: minSelect,
      maxSelect: maxSelect,
      sortOrder: (index + 1) * 10,
      options: [
        for (var i = 0; i < options.length; i++)
          options[i].toDraft(i, existingOptionGroups),
      ],
    );
  }

  void dispose() {
    nameController.dispose();
    maxSelectController.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

class _OptionForm {
  final TextEditingController skuController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController priceController = TextEditingController(
    text: '0',
  );
  final TextEditingController imageUrlController = TextEditingController();
  final List<_OptionGroupForm> childGroups = [];

  bool useExistingProduct = false;
  String? existingProductId;
  bool isActive = true;
  bool visibleInMenu = false;

  MerchantOptionDraft toDraft(
    int index,
    List<MerchantOptionGroup> existingOptionGroups,
  ) {
    return MerchantOptionDraft(
      productId: useExistingProduct ? existingProductId ?? '' : '',
      sku: skuController.text.trim(),
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
      basePrice: _readDouble(priceController.text),
      status: isActive ? 'active' : 'inactive',
      visibleInMenu: visibleInMenu,
      imageUrl: imageUrlController.text.trim(),
      sortOrder: (index + 1) * 10,
      childGroups: [
        for (var i = 0; i < childGroups.length; i++)
          childGroups[i].toDraft(i, existingOptionGroups),
      ],
    );
  }

  void dispose() {
    skuController.dispose();
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    imageUrlController.dispose();
    for (final group in childGroups) {
      group.dispose();
    }
  }
}

String? _validateOptionGroups(List<_OptionGroupForm> groups) {
  for (final group in groups) {
    if (group.useExistingGroup) {
      if (group.existingOptionGroupId == null) {
        return 'Choose an existing option group.';
      }
      continue;
    }

    final groupName = group.nameController.text.trim();
    if (groupName.isEmpty) return 'Option group name is required.';
    if (group.options.isEmpty) {
      return 'Option group "$groupName" needs at least one option.';
    }

    if (group.selectionType == 'multiple') {
      final maxSelect = int.tryParse(group.maxSelectController.text.trim());
      if (maxSelect == null || maxSelect < 1) {
        return 'Max choices for "$groupName" must be above 0.';
      }
      if (maxSelect > group.options.length) {
        return 'Max choices for "$groupName" cannot exceed option count.';
      }
    }

    for (final option in group.options) {
      if (option.useExistingProduct) {
        if (option.existingProductId == null) {
          return 'Choose an existing product in "$groupName".';
        }
      } else {
        final optionName = option.nameController.text.trim();
        if (optionName.isEmpty) {
          return 'Option name is required in "$groupName".';
        }
      }
      final childError = _validateOptionGroups(option.childGroups);
      if (childError != null) return childError;
    }
  }

  return null;
}

String _categoryLabel(
  MerchantCategory category,
  List<MerchantCategory> categories,
) {
  if (category.parentId == null) return category.name;
  MerchantCategory? parent;
  for (final item in categories) {
    if (item.id == category.parentId) {
      parent = item;
      break;
    }
  }
  if (parent == null) return category.name;
  return '${parent.name} / ${category.name}';
}

String _optionTitle(
  _OptionForm option,
  List<MerchantProduct> existingProducts,
  int index,
) {
  if (option.useExistingProduct) {
    for (final product in existingProducts) {
      if (product.id == option.existingProductId) {
        return product.name;
      }
    }
    return 'Existing option ${index + 1}';
  }

  final name = option.nameController.text.trim();
  return name.isEmpty ? 'Option ${index + 1}' : name;
}

MerchantOptionGroup? _findOptionGroup(
  List<MerchantOptionGroup> optionGroups,
  String? id,
) {
  if (id == null) return null;
  for (final optionGroup in optionGroups) {
    if (optionGroup.id == id) return optionGroup;
  }
  return null;
}

String? _requiredValidator(String? value) {
  return (value?.trim().isEmpty ?? true) ? 'Required' : null;
}

String? _moneyValidator(String? value) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a valid amount';
  if (parsed < 0) return 'Amount cannot be negative';
  return null;
}

double _readDouble(String value) {
  return double.tryParse(value.trim()) ?? 0;
}

int _readPositiveInt(String value, int fallback) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 1) return fallback < 1 ? 1 : fallback;
  return parsed;
}
