import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_reward.dart';
import 'signed_api_client.dart';

class MerchantRewardsProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUpdating = false;
  String? _errorMessage;
  List<MerchantReward> _rewards = const [];

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;
  List<MerchantReward> get rewards => _rewards;

  Future<void> fetchRewards({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantRewardsPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawRewards = response['rewards'] as List? ?? const [];
      _rewards = rawRewards
          .whereType<Map>()
          .map(
            (reward) => MerchantReward.fromJson(
              reward.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((reward) => reward.id.isNotEmpty)
          .toList(growable: false);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load rewards: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createReward({
    required SignedApiClient apiClient,
    required String token,
    required MerchantReward reward,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantRewardCreatePath,
        reward.toSaveJson(),
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _upsertReward(response['reward']);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to create reward: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateReward({
    required SignedApiClient apiClient,
    required String token,
    required MerchantReward reward,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantRewardUpdatePath,
        reward.toSaveJson(),
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _upsertReward(response['reward']);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update reward: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateRewardStatus({
    required SignedApiClient apiClient,
    required String token,
    required String rewardId,
    required bool active,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantRewardStatusPath,
        {'reward_id': rewardId, 'active': active},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _upsertReward(response['reward']);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update reward: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  void _upsertReward(dynamic rawReward) {
    if (rawReward is! Map) return;
    final reward = MerchantReward.fromJson(
      rawReward.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    if (reward.id.isEmpty) return;

    _rewards = [reward, ..._rewards.where((item) => item.id != reward.id)]
      ..sort(_compareRewards);
  }
}

int _compareRewards(MerchantReward a, MerchantReward b) {
  if (a.active != b.active) return a.active ? -1 : 1;
  final pointsCompare = a.pointsCost.compareTo(b.pointsCost);
  if (pointsCompare != 0) return pointsCompare;
  final sortCompare = a.sortOrder.compareTo(b.sortOrder);
  if (sortCompare != 0) return sortCompare;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}
