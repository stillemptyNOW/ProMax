import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:promax/core/webpush/max_web_socket.dart';
import 'package:promax/core/webpush/web_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('browser links accept only complete Apple Push subscriptions', () {
    final point = List<int>.filled(65, 1)..[0] = 4;
    Uri link(String endpoint, {String? auth}) => Uri(
      scheme: 'promax',
      host: 'webpush',
      queryParameters: {
        'endpoint': endpoint,
        'p256dh': base64Url.encode(point),
        'auth': auth ?? base64Url.encode(List<int>.filled(16, 2)),
      },
    );
    const endpoint = 'https://web.push.apple.com/synthetic';
    expect(
      WebPushSubscription.fromAppleLink(link(endpoint))?.endpoint,
      endpoint,
    );
    expect(
      WebPushSubscription.fromAppleLink(
        link('https://push.apple.com.example.test/synthetic'),
      ),
      isNull,
    );
    expect(
      WebPushSubscription.fromAppleLink(link(endpoint, auth: 'invalid')),
      isNull,
    );
  });

  test(
    'Web Push credentials and subscription follow the active account',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'webpush_login_token': 'unassigned-legacy-token',
        'webpush_endpoint': 'https://example.test/legacy',
        'webpush_login_token_101': 'synthetic-first-account-token',
        'webpush_endpoint_101': 'https://example.test/first',
        'webpush_device_id_101': 'synthetic-first-device',
      });
      final service = WebPushService.instance;

      await TokenStorage.setActiveAccount(101);
      expect(await service.isAuthorized(), isTrue);
      expect(
        (await service.linkInfo())?.endpoint,
        'https://example.test/first',
      );

      await TokenStorage.setActiveAccount(202);
      expect(await service.isAuthorized(), isFalse);
      expect(await service.linkInfo(), isNull);
      await expectLater(
        service.registerSubscription(
          const WebPushSubscription(
            endpoint: 'https://example.test/synthetic',
            publicKey: 'synthetic-public',
            authKey: 'synthetic-auth',
          ),
          expectedAccountId: 101,
        ),
        throwsA(
          isA<MaxWebException>().having(
            (error) => error.message,
            'message',
            contains('Аккаунт изменился'),
          ),
        ),
      );

      await TokenStorage.setActiveAccount(101);
      expect((await service.linkInfo())?.deviceId, 'synthetic-first-device');
    },
  );
}
