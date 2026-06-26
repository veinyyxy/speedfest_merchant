import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_category.dart';
import '../Models/merchant_option_group.dart';
import '../Models/merchant_product.dart';
import '../Models/merchant_product_create_request.dart';
import 'signed_api_client.dart';

class MerchantProductsProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isLoadingCategories = false;
  bool _isLoadingOptionGroups = false;
  bool _isUpdating = false;
  bool _isCreating = false;
  bool _isUploadingImage = false;
  String? _errorMessage;
  List<MerchantProduct> _products = const [];
  List<MerchantCategory> _categories = const [];
  List<MerchantOptionGroup> _optionGroups = const [];

  bool get isLoading => _isLoading;
  bool get isLoadingCategories => _isLoadingCategories;
  bool get isLoadingOptionGroups => _isLoadingOptionGroups;
  bool get isUpdating => _isUpdating;
  bool get isCreating => _isCreating;
  bool get isUploadingImage => _isUploadingImage;
  String? get errorMessage => _errorMessage;
  List<MerchantProduct> get products => _products;
  List<MerchantCategory> get categories => _categories;
  List<MerchantOptionGroup> get optionGroups => _optionGroups;

  Future<void> fetchProducts({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantProductsPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawProducts = response['products'] as List? ?? const [];
      _products = rawProducts
          .whereType<Map>()
          .map(
            (product) => MerchantProduct.fromJson(
              product.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load products: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCategories({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoadingCategories = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantCategoriesPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawCategories = response['categories'] as List? ?? const [];
      _categories = rawCategories
          .whereType<Map>()
          .map(
            (category) => MerchantCategory.fromJson(
              category.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((category) => category.id > 0)
          .toList(growable: false);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load categories: $e';
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  Future<MerchantCategory?> createCategory({
    required SignedApiClient apiClient,
    required String token,
    required String name,
    int? parentId,
  }) async {
    _isLoadingCategories = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{'name': name};
      if (parentId != null) {
        body['parent_id'] = parentId;
      }

      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantCategoryCreatePath,
        body,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final created = MerchantCategory.fromJson(
        Map<String, dynamic>.from(response['category']),
      );
      _categories =
          [
            ..._categories.where((category) => category.id != created.id),
            created,
          ]..sort((a, b) {
            final parentCompare = (a.parentId ?? 0).compareTo(b.parentId ?? 0);
            if (parentCompare != 0) return parentCompare;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
      return created;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (e) {
      _errorMessage = 'Unable to create category: $e';
      return null;
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  Future<void> fetchOptionGroups({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoadingOptionGroups = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantOptionGroupsPath,
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawGroups = response['option_groups'] as List? ?? const [];
      _optionGroups = rawGroups
          .whereType<Map>()
          .map(
            (group) => MerchantOptionGroup.fromJson(
              group.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((group) => group.id.isNotEmpty)
          .toList(growable: false);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load option groups: $e';
    } finally {
      _isLoadingOptionGroups = false;
      notifyListeners();
    }
  }

  Future<bool> createProduct({
    required SignedApiClient apiClient,
    required String token,
    required MerchantProductCreateRequest request,
  }) async {
    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantProductCreatePath,
        request.toJson(),
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawProduct = response['product'];
      if (rawProduct is Map) {
        final created = MerchantProduct.fromJson(
          rawProduct.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        _products = [
          created,
          ..._products.where((product) => product.id != created.id),
        ];
      }
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to create product: $e';
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<String?> uploadProductImage({
    required SignedApiClient apiClient,
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    _isUploadingImage = true;
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
      if (imageUrl.isEmpty) {
        _errorMessage = 'Image upload did not return a URL.';
        return null;
      }
      return imageUrl;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (e) {
      _errorMessage = 'Unable to upload image: $e';
      return null;
    } finally {
      _isUploadingImage = false;
      notifyListeners();
    }
  }

  Future<bool> updateProduct({
    required SignedApiClient apiClient,
    required String token,
    required MerchantProductCreateRequest request,
  }) async {
    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantProductUpdatePath,
        request.toJson(),
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final updated = MerchantProduct.fromJson(
        Map<String, dynamic>.from(response['product']),
      );
      _products = _products
          .map((product) => product.id == updated.id ? updated : product)
          .toList(growable: false);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update product: $e';
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<bool> updateProductStatus({
    required SignedApiClient apiClient,
    required String token,
    required String productId,
    required String status,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantProductStatusUpdatePath,
        {'product_id': productId, 'status': status},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final updated = MerchantProduct.fromJson(
        Map<String, dynamic>.from(response['product']),
      );
      _products = _products
          .map((product) => product.id == updated.id ? updated : product)
          .toList(growable: false);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update product: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> updateProductMenuVisibility({
    required SignedApiClient apiClient,
    required String token,
    required String productId,
    required bool visibleInMenu,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantProductMenuVisibilityUpdatePath,
        {'product_id': productId, 'visible_in_menu': visibleInMenu},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final updated = MerchantProduct.fromJson(
        Map<String, dynamic>.from(response['product']),
      );
      _products = _products
          .map((product) => product.id == updated.id ? updated : product)
          .toList(growable: false);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to update product menu visibility: $e';
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }
}
