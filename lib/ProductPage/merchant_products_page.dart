import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_service_config.dart';
import '../Controller/merchant_products_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_product.dart';
import 'merchant_product_editor_page.dart';

class MerchantProductsPage extends StatefulWidget {
  const MerchantProductsPage({super.key});

  @override
  State<MerchantProductsPage> createState() => _MerchantProductsPageState();
}

class _MerchantProductsPageState extends State<MerchantProductsPage> {
  final _searchController = TextEditingController();
  bool _loaded = false;
  String _statusFilter = 'all';
  String _typeFilter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProducts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantProductsProvider>().fetchProducts(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _openCreateProduct() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MerchantProductEditorPage()),
    );
    if (created == true && mounted) {
      await _fetchProducts();
    }
  }

  Future<void> _openEditProduct(MerchantProduct product) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchantProductEditorPage(product: product),
      ),
    );
    if (updated == true && mounted) {
      await _fetchProducts();
    }
  }

  Future<void> _setProductActive(MerchantProduct product, bool isActive) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final productsProvider = context.read<MerchantProductsProvider>();
    final status = isActive ? 'active' : 'inactive';
    final ok = await productsProvider.updateProductStatus(
      apiClient: session.apiClient,
      token: token,
      productId: product.id,
      status: status,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${product.name} is now $status.'
              : productsProvider.errorMessage ??
                    'Product could not be updated.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (ok) {
      await _fetchProducts();
    }
  }

  Future<void> _setProductVisibleInMenu(
    MerchantProduct product,
    bool visibleInMenu,
  ) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final productsProvider = context.read<MerchantProductsProvider>();
    final ok = await productsProvider.updateProductMenuVisibility(
      apiClient: session.apiClient,
      token: token,
      productId: product.id,
      visibleInMenu: visibleInMenu,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${product.name} menu visibility updated.'
              : productsProvider.errorMessage ??
                    'Product visibility could not be updated.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (ok) {
      await _fetchProducts();
    }
  }

  List<MerchantProduct> _filteredProducts(List<MerchantProduct> products) {
    final query = _searchController.text.trim().toLowerCase();
    return products
        .where((product) {
          final matchesStatus =
              _statusFilter == 'all' || product.status == _statusFilter;
          final matchesType = switch (_typeFilter) {
            'menu' => product.visibleInMenu,
            'options' => product.isOptionProduct,
            'hidden' => !product.visibleInMenu,
            _ => true,
          };
          final matchesQuery =
              query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              product.sku.toLowerCase().contains(query) ||
              product.categoryLabel.toLowerCase().contains(query);
          return matchesStatus && matchesType && matchesQuery;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantProductsProvider>();
    final products = _filteredProducts(provider.products);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Add product',
            onPressed: _openCreateProduct,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : _fetchProducts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search products',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          _ProductFilterBar(
            selectedStatus: _statusFilter,
            onSelected: (status) {
              setState(() => _statusFilter = status);
            },
          ),
          _ProductTypeFilterBar(
            selectedType: _typeFilter,
            onSelected: (type) {
              setState(() => _typeFilter = type);
            },
          ),
          Expanded(
            child: _ProductsBody(
              isLoading: provider.isLoading,
              errorMessage: provider.errorMessage,
              products: products,
              onRefresh: _fetchProducts,
              onEdit: _openEditProduct,
              onToggleActive: _setProductActive,
              onToggleMenuVisibility: _setProductVisibleInMenu,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductFilterBar extends StatelessWidget {
  const _ProductFilterBar({
    required this.selectedStatus,
    required this.onSelected,
  });

  final String selectedStatus;
  final ValueChanged<String> onSelected;

  static const filters = [
    ('all', 'All'),
    ('active', 'Active'),
    ('inactive', 'Inactive'),
    ('archived', 'Archived'),
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
            label: Text(filter.$2),
            selected: selectedStatus == filter.$1,
            onSelected: (_) => onSelected(filter.$1),
          );
        },
      ),
    );
  }
}

class _ProductTypeFilterBar extends StatelessWidget {
  const _ProductTypeFilterBar({
    required this.selectedType,
    required this.onSelected,
  });

  final String selectedType;
  final ValueChanged<String> onSelected;

  static const filters = [
    ('all', 'All products'),
    ('menu', 'Buyer menu'),
    ('options', 'Options'),
    ('hidden', 'Hidden'),
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
            label: Text(filter.$2),
            selected: selectedType == filter.$1,
            onSelected: (_) => onSelected(filter.$1),
          );
        },
      ),
    );
  }
}

class _ProductsBody extends StatelessWidget {
  const _ProductsBody({
    required this.isLoading,
    required this.errorMessage,
    required this.products,
    required this.onRefresh,
    required this.onEdit,
    required this.onToggleActive,
    required this.onToggleMenuVisibility,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<MerchantProduct> products;
  final Future<void> Function() onRefresh;
  final void Function(MerchantProduct product) onEdit;
  final void Function(MerchantProduct product, bool isActive) onToggleActive;
  final void Function(MerchantProduct product, bool visibleInMenu)
  onToggleMenuVisibility;

  @override
  Widget build(BuildContext context) {
    if (isLoading && products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null && products.isEmpty) {
      return _StateMessage(
        icon: Icons.error_outline,
        title: 'Products could not be loaded',
        message: errorMessage!,
        onPressed: onRefresh,
      );
    }

    if (products.isEmpty) {
      return _StateMessage(
        icon: Icons.restaurant_menu_outlined,
        title: 'No products found',
        message: 'Try another filter or refresh products.',
        onPressed: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductCard(
            product: product,
            onEdit: () => onEdit(product),
            onToggleActive: (value) => onToggleActive(product, value),
            onToggleMenuVisibility: (value) =>
                onToggleMenuVisibility(product, value),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onToggleActive,
    required this.onToggleMenuVisibility,
  });

  final MerchantProduct product;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;
  final ValueChanged<bool> onToggleMenuVisibility;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _resolveImageUrl(product.imageUrl);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 72,
                height: 72,
                color: Colors.grey.shade200,
                child: imageUrl.isEmpty
                    ? Icon(
                        Icons.restaurant_outlined,
                        color: Colors.grey.shade600,
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey.shade600,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.end,
                            children: [
                              if (product.isOptionProduct)
                                const _OptionProductChip(),
                              _MenuVisibilityChip(
                                visibleInMenu: product.visibleInMenu,
                              ),
                              _StatusChip(status: product.status),
                              IconButton(
                                tooltip: 'Edit product',
                                onPressed: onEdit,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  _ProductRatingSummary(product: product),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'CAD \$${product.basePrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        'Buyer menu',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Switch(
                        value: product.visibleInMenu,
                        onChanged: onToggleMenuVisibility,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        product.isActive ? 'Available' : 'Paused',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      Switch(
                        value: product.isActive,
                        onChanged: product.status == 'archived'
                            ? null
                            : onToggleActive,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRatingSummary extends StatelessWidget {
  const _ProductRatingSummary({required this.product});

  final MerchantProduct product;

  @override
  Widget build(BuildContext context) {
    final hasRatings = product.hasRatings;
    final color = hasRatings ? Colors.amber.shade800 : Colors.grey.shade600;
    final label = hasRatings
        ? '${product.ratingAverage.toStringAsFixed(1)} (${product.ratingCount})'
        : 'No ratings yet';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasRatings ? Icons.star_rounded : Icons.star_border_rounded,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: hasRatings ? Colors.grey.shade800 : Colors.grey.shade600,
            fontSize: 12,
            fontWeight: hasRatings ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _OptionProductChip extends StatelessWidget {
  const _OptionProductChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Option',
        style: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MenuVisibilityChip extends StatelessWidget {
  const _MenuVisibilityChip({required this.visibleInMenu});

  final bool visibleInMenu;

  @override
  Widget build(BuildContext context) {
    final color = visibleInMenu ? Colors.teal.shade700 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        visibleInMenu ? 'Buyer menu' : 'Hidden',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => Colors.green.shade700,
      'archived' => Colors.grey.shade700,
      _ => Colors.orange.shade800,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty ? 'Unknown' : _humanize(status),
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

String _resolveImageUrl(String imageUrl) {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://')) {
    return trimmed;
  }
  return '${MerchantServiceConfig.baseUrl}$trimmed';
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
