import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_user.dart';
import 'merchant_notification_service.dart';
import 'signed_api_client.dart';

class MerchantSessionProvider with ChangeNotifier {
  MerchantSessionProvider({
    SignedApiClient? apiClient,
    SignedApiClient? backgroundApiClient,
  }) {
    this.apiClient = apiClient ?? SignedApiClient();
    this.backgroundApiClient =
        backgroundApiClient ??
        SignedApiClient(
          baseUrl: this.apiClient.baseUrl,
          clientId: this.apiClient.clientId,
          hmacSecretKey: this.apiClient.hmacSecretKey,
        );
    assert(!identical(this.apiClient, this.backgroundApiClient));
    this.apiClient.onAuthenticationFailure = _handleAuthenticationFailure;
    this.backgroundApiClient.onAuthenticationFailure =
        _handleAuthenticationFailure;
  }

  late final SignedApiClient apiClient;
  late final SignedApiClient backgroundApiClient;

  bool _isInitializing = true;
  bool _isLoggingIn = false;
  bool _isLoggingOut = false;
  String? _token;
  MerchantUser? _merchantUser;
  String? _errorMessage;

  bool get isInitializing => _isInitializing;
  bool get isLoggingIn => _isLoggingIn;
  bool get isLoggingOut => _isLoggingOut;
  bool get isLoggedIn => _token != null && _merchantUser != null;
  String? get token => _token;
  MerchantUser? get merchantUser => _merchantUser;
  String? get errorMessage => _errorMessage;
  bool can(String permission) =>
      _merchantUser?.hasPermission(permission) ?? false;
  bool canAny(Iterable<String> permissions) => permissions.any(can);

  void _handleAuthenticationFailure(AppException exception) {
    if (_token == null && _merchantUser == null) return;
    _resetConnections();
    _token = null;
    _merchantUser = null;
    _errorMessage = exception.message;
    notifyListeners();
  }

  void resetBackgroundConnection() {
    backgroundApiClient.resetConnection();
  }

  void _resetConnections() {
    apiClient.resetConnection();
    backgroundApiClient.resetConnection();
  }

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
        retryOnConnectionFailure: true,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);

      if (response['success'] != true) {
        _errorMessage = response['error']?.toString() ?? 'Login failed';
        return false;
      }

      _token = response['token']?.toString();
      final userMap = Map<String, dynamic>.from(response['merchant_user']);
      userMap['permissions'] =
          response['permissions'] ?? userMap['permissions'];
      _merchantUser = MerchantUser.fromJson(userMap);

      final token = _token;
      if (token != null &&
          token.isNotEmpty &&
          _merchantUser?.mustChangePassword != true) {
        await MerchantNotificationService.instance.registerForMerchant(
          apiClient: apiClient,
          token: token,
        );
      }

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
        retryOnConnectionFailure: true,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      if (response['success'] != true) {
        await logout(callServer: false);
        return false;
      }

      final userMap = Map<String, dynamic>.from(response['merchant_user']);
      userMap['permissions'] =
          response['permissions'] ?? userMap['permissions'];
      _merchantUser = MerchantUser.fromJson(userMap);
      final token = _token;
      if (token != null &&
          token.isNotEmpty &&
          _merchantUser?.mustChangePassword != true) {
        await MerchantNotificationService.instance.registerForMerchant(
          apiClient: apiClient,
          token: token,
        );
      }
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

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) return false;

    _errorMessage = null;
    notifyListeners();
    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantPasswordChangePath,
        {'current_password': currentPassword, 'new_password': newPassword},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _token = response['token']?.toString() ?? token;
      final userMap = Map<String, dynamic>.from(response['merchant_user']);
      userMap['permissions'] =
          response['permissions'] ?? userMap['permissions'];
      _merchantUser = MerchantUser.fromJson(userMap);
      await MerchantNotificationService.instance.registerForMerchant(
        apiClient: apiClient,
        token: _token!,
      );
      notifyListeners();
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Unable to change password: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout({bool callServer = true}) async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    notifyListeners();

    final oldToken = _token;
    try {
      if (oldToken != null && oldToken.isNotEmpty) {
        await MerchantNotificationService.instance.deactivateForMerchant(
          apiClient: apiClient,
          token: oldToken,
        );
      }

      if (callServer && oldToken != null && oldToken.isNotEmpty) {
        await apiClient.post(
          MerchantServiceConfig.merchantLogoutPath,
          <String, dynamic>{},
          token: oldToken,
        );
      }
    } catch (_) {
      // Local logout should succeed even if the server request fails.
    } finally {
      _resetConnections();
      _token = null;
      _merchantUser = null;
      _errorMessage = null;
      _isLoggingOut = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    apiClient.close();
    backgroundApiClient.close();
    super.dispose();
  }
}
