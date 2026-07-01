import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_buyer_config.dart';
import 'signed_api_client.dart';

class MerchantSettingsProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  String? _errorMessage;
  MerchantBuyerConfig? _buyerConfig;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isUploadingLogo => _isUploadingLogo;
  String? get errorMessage => _errorMessage;
  MerchantBuyerConfig? get buyerConfig => _buyerConfig;

  Future<void> fetchBuyerConfig({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantBuyerConfigPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _buyerConfig = MerchantBuyerConfig.fromJson(
        Map<String, dynamic>.from(response['config'] as Map),
      );
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load settings: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveBuyerConfig({
    required SignedApiClient apiClient,
    required String token,
    required MerchantBuyerConfig config,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantBuyerConfigPath,
        {'config': config.toJson()},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _buyerConfig = MerchantBuyerConfig.fromJson(
        Map<String, dynamic>.from(response['config'] as Map),
      );
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to save settings: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<MerchantImageUploadResult?> uploadStoreLogo({
    required SignedApiClient apiClient,
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    _isUploadingLogo = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.uploadFile(
        MerchantServiceConfig.merchantImageUploadPath,
        fieldName: 'image',
        bytes: bytes,
        filename: filename,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final imageUrl = response['image_url']?.toString().trim() ?? '';
      final assetId = response['asset_id']?.toString().trim() ?? '';
      if (imageUrl.isEmpty) {
        _errorMessage = 'Logo upload did not return a URL.';
        return null;
      }
      return MerchantImageUploadResult(assetId: assetId, imageUrl: imageUrl);
    } on AppException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (e) {
      _errorMessage = 'Unable to upload logo: $e';
      return null;
    } finally {
      _isUploadingLogo = false;
      notifyListeners();
    }
  }
}

class MerchantImageUploadResult {
  const MerchantImageUploadResult({
    required this.assetId,
    required this.imageUrl,
  });

  final String assetId;
  final String imageUrl;
}
