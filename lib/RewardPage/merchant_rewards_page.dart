import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Controller/merchant_rewards_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_reward.dart';
import 'merchant_reward_editor_page.dart';

class MerchantRewardsPage extends StatefulWidget {
  const MerchantRewardsPage({super.key});

  @override
  State<MerchantRewardsPage> createState() => _MerchantRewardsPageState();
}

class _MerchantRewardsPageState extends State<MerchantRewardsPage> {
  final _searchController = TextEditingController();
  bool _loaded = false;
  String _statusFilter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRewards());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRewards() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    await context.read<MerchantRewardsProvider>().fetchRewards(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _openCreateReward() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MerchantRewardEditorPage()),
    );
    if (created == true && mounted) {
      await _fetchRewards();
    }
  }

  Future<void> _openEditReward(MerchantReward reward) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchantRewardEditorPage(reward: reward),
      ),
    );
    if (updated == true && mounted) {
      await _fetchRewards();
    }
  }

  Future<void> _setRewardActive(MerchantReward reward, bool active) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;

    final rewardsProvider = context.read<MerchantRewardsProvider>();
    final ok = await rewardsProvider.updateRewardStatus(
      apiClient: session.apiClient,
      token: token,
      rewardId: reward.id,
      active: active,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${reward.title} is now ${active ? 'active' : 'inactive'}.'
              : rewardsProvider.errorMessage ?? 'Reward could not be updated.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (ok) {
      await _fetchRewards();
    }
  }

  List<MerchantReward> _filteredRewards(List<MerchantReward> rewards) {
    final query = _searchController.text.trim().toLowerCase();
    return rewards
        .where((reward) {
          final matchesStatus = switch (_statusFilter) {
            'active' => reward.active,
            'inactive' => !reward.active,
            _ => true,
          };
          final matchesQuery =
              query.isEmpty ||
              reward.title.toLowerCase().contains(query) ||
              reward.description.toLowerCase().contains(query) ||
              reward.pointsCost.toString().contains(query);
          return matchesStatus && matchesQuery;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantRewardsProvider>();
    final rewards = _filteredRewards(provider.rewards);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards'),
        actions: [
          IconButton(
            tooltip: 'Add reward',
            onPressed: _openCreateReward,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : _fetchRewards,
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
                hintText: 'Search rewards',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          _RewardFilterBar(
            selectedStatus: _statusFilter,
            onSelected: (status) => setState(() => _statusFilter = status),
          ),
          Expanded(
            child: _RewardsBody(
              isLoading: provider.isLoading,
              errorMessage: provider.errorMessage,
              rewards: rewards,
              onRefresh: _fetchRewards,
              onEdit: _openEditReward,
              onToggleActive: _setRewardActive,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardFilterBar extends StatelessWidget {
  const _RewardFilterBar({
    required this.selectedStatus,
    required this.onSelected,
  });

  final String selectedStatus;
  final ValueChanged<String> onSelected;

  static const filters = [
    ('all', 'All'),
    ('active', 'Active'),
    ('inactive', 'Inactive'),
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

class _RewardsBody extends StatelessWidget {
  const _RewardsBody({
    required this.isLoading,
    required this.errorMessage,
    required this.rewards,
    required this.onRefresh,
    required this.onEdit,
    required this.onToggleActive,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<MerchantReward> rewards;
  final Future<void> Function() onRefresh;
  final void Function(MerchantReward reward) onEdit;
  final void Function(MerchantReward reward, bool active) onToggleActive;

  @override
  Widget build(BuildContext context) {
    if (isLoading && rewards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null && rewards.isEmpty) {
      return _StateMessage(
        icon: Icons.error_outline,
        title: 'Rewards could not be loaded',
        message: errorMessage!,
        onPressed: onRefresh,
      );
    }

    if (rewards.isEmpty) {
      return _StateMessage(
        icon: Icons.redeem_outlined,
        title: 'No rewards found',
        message: 'Create a discount reward or try another filter.',
        onPressed: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: rewards.length,
        itemBuilder: (context, index) {
          final reward = rewards[index];
          return _RewardCard(
            reward: reward,
            onEdit: () => onEdit(reward),
            onToggleActive: (value) => onToggleActive(reward, value),
          );
        },
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.onEdit,
    required this.onToggleActive,
  });

  final MerchantReward reward;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withAlpha(28),
              child: Icon(
                reward.isProductReward
                    ? Icons.restaurant_menu_outlined
                    : Icons.local_offer_outlined,
                color: Theme.of(context).colorScheme.primary,
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
                          reward.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(active: reward.active),
                      IconButton(
                        tooltip: 'Edit reward',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  if (reward.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      reward.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.stars_outlined,
                        label: '${reward.pointsCost} pts',
                      ),
                      _InfoChip(
                        icon: reward.isProductReward
                            ? Icons.fastfood_outlined
                            : Icons.payments_outlined,
                        label: reward.valueLabel,
                      ),
                      _InfoChip(
                        icon: Icons.schedule_outlined,
                        label: '${reward.expiresInDays} days',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Visible to customers',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const Spacer(),
                      Switch(value: reward.active, onChanged: onToggleActive),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade700),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green.shade700 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
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
