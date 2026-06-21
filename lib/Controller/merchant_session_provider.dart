import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_user.dart';
import 'signed_api_client.dart';

class MerchantSessionProvider with ChangeNotifier {
  MerchantSessionProvider({SignedApiClient? apiClient})
    : apiClient = apiClient ?? SignedApiClient();

  final SignedApiClient apiClient;

  bool _isInitializing = true;
  bool _isLoggingIn = false;
  String? _token;
  MerchantUser? _merchantUser;
  String? _errorMessage;

  bool get isInitializing => _isInitializing;
  bool get isLoggingIn => _isLoggingIn;
  bool get isLoggedIn => _token != null && _merchantUser != null;
  String? get token => _token;
  MerchantUser? get merchantUser => _merchantUser;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    _isInitializing = false;
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _isLoggingIn = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantLoginPath,
        {'username': username.trim(), 'password': password},
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);

      if (response['success'] != true) {
        _errorMessage = response['error']?.toString() ?? 'Login failed';
        return false;
      }

      _token = response['token']?.toString();
      final userMap = Map<String, dynamic>.from(response['merchant_user']);
      _merchantUser = MerchantUser.fromJson(userMap);

      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unexpected login error: $e';
      return false;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<bool> validateSession() async {
    if (_token == null || _token!.isEmpty) return false;

    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantValidatePath,
        <String, dynamic>{},
        token: _token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      if (response['success'] != true) {
        await logout(callServer: false);
        return false;
      }

      _merchantUser = MerchantUser.fromJson(
        Map<String, dynamic>.from(response['merchant_user']),
      );
      return true;
    } on AppException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await logout(callServer: false);
      }
      _errorMessage = e.message;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout({bool callServer = true}) async {
    final oldToken = _token;
    _token = null;
    _merchantUser = null;
    _errorMessage = null;
    notifyListeners();

    if (callServer && oldToken != null && oldToken.isNotEmpty) {
      try {
        await apiClient.post(
          MerchantServiceConfig.merchantLogoutPath,
          <String, dynamic>{},
          token: oldToken,
        );
      } catch (_) {
        // Local logout should succeed even if the server request fails.
      }
    }
  }
}
