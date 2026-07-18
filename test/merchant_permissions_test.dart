import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speedfest_merchant/Common/merchant_permissions.dart';
import 'package:speedfest_merchant/Controller/signed_api_client.dart';
import 'package:speedfest_merchant/Models/merchant_managed_user.dart';
import 'package:speedfest_merchant/Models/merchant_user.dart';

void main() {
  test('merchant user reads permissions and owner keeps full access', () {
    final staff = MerchantUser.fromJson({
      'merchant_user_id': 'staff-id',
      'username': 'staff',
      'role': 'staff',
      'permissions': [MerchantPermissions.ordersView],
    });
    final owner = MerchantUser.fromJson({
      'merchant_user_id': 'owner-id',
      'username': 'owner',
      'role': 'owner',
      'permissions': const <String>[],
    });

    expect(staff.hasPermission(MerchantPermissions.ordersView), isTrue);
    expect(staff.hasPermission(MerchantPermissions.ordersRefund), isFalse);
    expect(owner.hasPermission(MerchantPermissions.usersManage), isTrue);
  });

  test('managed user parses effective permissions and overrides', () {
    final user = MerchantManagedUser.fromJson({
      'merchant_user_id': 'user-id',
      'username': 'counter',
      'role': 'staff',
      'permissions': [
        MerchantPermissions.ordersView,
        MerchantPermissions.ordersPrint,
      ],
      'permission_overrides': [
        {'permission_key': MerchantPermissions.ordersRefund, 'effect': 'allow'},
        {'permission_key': MerchantPermissions.productsView, 'effect': 'deny'},
      ],
    });

    expect(user.permissions, contains(MerchantPermissions.ordersPrint));
    expect(user.permissionOverrides[MerchantPermissions.ordersRefund], 'allow');
    expect(user.permissionOverrides[MerchantPermissions.productsView], 'deny');
  });

  test(
    'authenticated 401 invokes the shared authentication failure hook',
    () async {
      AppException? authFailure;
      final client = SignedApiClient(
        baseUrl: 'https://merchant.test',
        clientId: 'test-client',
        hmacSecretKey: 'test-secret',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"success":false,"code":"MERCHANT_REAUTHENTICATION_REQUIRED","error":"Login again"}',
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
        onAuthenticationFailure: (exception) => authFailure = exception,
      );

      await expectLater(
        client.post('/api/merchant/orders', const {}, token: 'old-token'),
        throwsA(isA<AppException>()),
      );
      expect(authFailure?.code, 'MERCHANT_REAUTHENTICATION_REQUIRED');
    },
  );

  test('permission denied does not invalidate the shared session', () async {
    var invalidated = false;
    final client = SignedApiClient(
      baseUrl: 'https://merchant.test',
      clientId: 'test-client',
      hmacSecretKey: 'test-secret',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"success":false,"code":"MERCHANT_PERMISSION_DENIED","error":"Denied"}',
          403,
          headers: {'content-type': 'application/json'},
        ),
      ),
      onAuthenticationFailure: (_) => invalidated = true,
    );

    await expectLater(
      client.post('/api/merchant/orders', const {}, token: 'valid-token'),
      throwsA(isA<AppException>()),
    );
    expect(invalidated, isFalse);
  });
}
