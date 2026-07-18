import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_managed_user.dart';
import 'signed_api_client.dart';

class MerchantUsersProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  List<MerchantManagedUser> _users = const [];
  List<MerchantPermissionDefinition> _permissionCatalog = const [];
  Map<String, Set<String>> _roleDefaults = const {};

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  List<MerchantManagedUser> get users => _users;
  List<MerchantPermissionDefinition> get permissionCatalog =>
      _permissionCatalog;
  Map<String, Set<String>> get roleDefaults => _roleDefaults;

  Future<void> fetchAll({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final responses = await Future.wait([
        apiClient.get(MerchantServiceConfig.merchantUsersPath, token: token),
        apiClient.get(
          MerchantServiceConfig.merchantUserPermissionsPath,
          token: token,
        ),
      ]);
      final usersResponse = Map<String, dynamic>.from(responses[0] as Map);
      final permissionsResponse = Map<String, dynamic>.from(
        responses[1] as Map,
      );
      _users = (usersResponse['users'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MerchantManagedUser.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
      _permissionCatalog =
          (permissionsResponse['permissions'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) => MerchantPermissionDefinition.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList(growable: false)
            ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      final rawDefaults = permissionsResponse['role_defaults'];
      _roleDefaults = {
        for (final role in const ['owner', 'manager', 'staff'])
          role: rawDefaults is Map
              ? _readStringSet(rawDefaults[role])
              : <String>{},
      };
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load merchant users: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required SignedApiClient apiClient,
    required String token,
    required String username,
    required String displayName,
    required String role,
    required String password,
  }) {
    return _saveUser(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantUserCreatePath,
      body: {
        'username': username,
        'display_name': displayName,
        'role': role,
        'password': password,
      },
    );
  }

  Future<bool> updateUser({
    required SignedApiClient apiClient,
    required String token,
    required String merchantUserId,
    required String displayName,
    required String role,
    required bool active,
  }) {
    return _saveUser(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantUserUpdatePath,
      body: {
        'merchant_user_id': merchantUserId,
        'display_name': displayName,
        'role': role,
        'active': active,
      },
    );
  }

  Future<bool> updatePermissions({
    required SignedApiClient apiClient,
    required String token,
    required String merchantUserId,
    required Map<String, String> overrides,
  }) {
    return _saveUser(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantUserPermissionsUpdatePath,
      body: {
        'merchant_user_id': merchantUserId,
        'overrides': [
          for (final entry in overrides.entries)
            {'permission_key': entry.key, 'effect': entry.value},
        ],
      },
    );
  }

  Future<bool> resetPassword({
    required SignedApiClient apiClient,
    required String token,
    required String merchantUserId,
    required String password,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await apiClient.post(
        MerchantServiceConfig.merchantUserPasswordResetPath,
        {'merchant_user_id': merchantUserId, 'password': password},
        token: token,
      );
      await fetchAll(apiClient: apiClient, token: token);
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to reset password: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> _saveUser({
    required SignedApiClient apiClient,
    required String token,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final rawResponse = await apiClient.post(path, body, token: token);
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawUser = response['user'];
      if (rawUser is Map) {
        _replaceUser(
          MerchantManagedUser.fromJson(Map<String, dynamic>.from(rawUser)),
        );
      }
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to save merchant user: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _replaceUser(MerchantManagedUser user) {
    final next = [..._users];
    final index = next.indexWhere((item) => item.id == user.id);
    if (index == -1) {
      next.add(user);
    } else {
      next[index] = user;
    }
    next.sort(_compareUsers);
    _users = next;
  }
}

Set<String> _readStringSet(dynamic value) {
  if (value is! List) return <String>{};
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet();
}

int _compareUsers(MerchantManagedUser left, MerchantManagedUser right) {
  if (left.active != right.active) return left.active ? -1 : 1;
  const roleOrder = {'owner': 0, 'manager': 1, 'staff': 2};
  final roleCompare = (roleOrder[left.role] ?? 3).compareTo(
    roleOrder[right.role] ?? 3,
  );
  if (roleCompare != 0) return roleCompare;
  return left.resolvedName.toLowerCase().compareTo(
    right.resolvedName.toLowerCase(),
  );
}
