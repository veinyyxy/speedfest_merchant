import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speedfest_merchant/Controller/merchant_session_provider.dart';
import 'package:speedfest_merchant/Controller/signed_api_client.dart';

void main() {
  const connectionClosedMessage =
      'Connection closed before full header was received';

  test('session uses separate clients for UI and background work', () {
    final session = MerchantSessionProvider();
    addTearDown(session.dispose);

    expect(identical(session.apiClient, session.backgroundApiClient), isFalse);
    expect(session.backgroundApiClient.baseUrl, session.apiClient.baseUrl);
    expect(session.backgroundApiClient.clientId, session.apiClient.clientId);
  });

  test('GET replaces a stale connection and retries once', () async {
    var factoryCalls = 0;
    var requestCalls = 0;
    final client = SignedApiClient(
      baseUrl: 'https://merchant.test',
      clientId: 'test-client',
      hmacSecretKey: 'test-secret',
      httpClientFactory: () {
        factoryCalls++;
        final clientNumber = factoryCalls;
        return MockClient((_) async {
          requestCalls++;
          if (clientNumber == 1) {
            throw http.ClientException(connectionClosedMessage);
          }
          return http.Response(
            '{"success":true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        });
      },
    );
    addTearDown(client.close);

    final response = await client.get('/api/merchant/products');

    expect(response, {'success': true});
    expect(factoryCalls, 2);
    expect(requestCalls, 2);
  });

  test('POST does not retry an unsafe operation by default', () async {
    var factoryCalls = 0;
    var requestCalls = 0;
    final client = SignedApiClient(
      baseUrl: 'https://merchant.test',
      clientId: 'test-client',
      hmacSecretKey: 'test-secret',
      httpClientFactory: () {
        factoryCalls++;
        return MockClient((_) async {
          requestCalls++;
          throw http.ClientException(connectionClosedMessage);
        });
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.post('/api/merchant/orders/order-id/refund', {'amount': 5}),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          contains(connectionClosedMessage),
        ),
      ),
    );

    expect(requestCalls, 1);
    expect(factoryCalls, 2);
  });

  test('an explicitly retryable POST replaces the connection once', () async {
    var factoryCalls = 0;
    var requestCalls = 0;
    final client = SignedApiClient(
      baseUrl: 'https://merchant.test',
      clientId: 'test-client',
      hmacSecretKey: 'test-secret',
      httpClientFactory: () {
        factoryCalls++;
        final clientNumber = factoryCalls;
        return MockClient((_) async {
          requestCalls++;
          if (clientNumber == 1) {
            throw http.ClientException(connectionClosedMessage);
          }
          return http.Response(
            '{"success":true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        });
      },
    );
    addTearDown(client.close);

    final response = await client.post('/api/merchant/auth/login', const {
      'username': 'owner',
      'password': 'password',
    }, retryOnConnectionFailure: true);

    expect(response, {'success': true});
    expect(factoryCalls, 2);
    expect(requestCalls, 2);
  });
}
