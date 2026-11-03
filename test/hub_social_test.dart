import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/core/hub/hub_content.dart';
import 'package:promax/core/hub/hub_social.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('HubConsent & HubPeer models', () {
    test('HubConsent defaults to false for opt-in privacy', () {
      const consent = HubConsent.defaults;
      expect(consent.showOs, isFalse);
      expect(consent.showPromax, isFalse);
      expect(consent.allowGroups, isFalse);
      expect(consent.shareWallpaper, isFalse);
    });

    test('HubConsent json roundtrip', () {
      const consent = HubConsent(showOs: true, showPromax: true);
      final json = consent.toJson();
      final restored = HubConsent.fromJson(json);
      expect(restored.showOs, isTrue);
      expect(restored.showPromax, isTrue);
      expect(restored.allowGroups, isFalse);
    });

    test('HubPeer reports online status correctly based on os and expiry', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final activePeer = HubPeer(
        accountId: 101,
        os: 'android',
        osExpires: now + 60,
        promax: true,
      );
      expect(activePeer.isOnline(nowSeconds: now), isTrue);

      final expiredPeer = HubPeer(
        accountId: 102,
        os: 'ios',
        osExpires: now - 10,
        promax: true,
      );
      expect(expiredPeer.isOnline(nowSeconds: now), isFalse);

      const noOsPeer = HubPeer(accountId: 103, promax: true);
      expect(noOsPeer.isOnline(nowSeconds: now), isFalse);
    });
  });

  group('HubClient social endpoints', () {
    test('calls identity consent, pulse, peers and delete', () async {
      final recordedRequests = <String, Map<String, dynamic>>{};
      final mock = MockClient((request) async {
        final path = request.url.path;
        final body = request.body.isNotEmpty
            ? jsonDecode(request.body) as Map<String, dynamic>
            : <String, dynamic>{};
        recordedRequests[path] = {
          'method': request.method,
          'auth': request.headers['Authorization'],
          'body': body,
        };

        if (path == '/v1/identity/config') {
          return http.Response(
            jsonEncode({'ready': true, 'bot_id': 12345}),
            200,
          );
        }
        if (path == '/v1/identity/session') {
          return http.Response(
            jsonEncode({'token': 'synthetic-token', 'account_id': 101}),
            200,
          );
        }
        if (path == '/v1/identity/me') {
          if (request.method == 'DELETE') {
            return http.Response(jsonEncode({'deleted': true}), 200);
          }
          return http.Response(
            jsonEncode({
              'account_id': 101,
              'consent': {
                'show_os': true,
                'show_promax': false,
                'allow_groups': false,
                'share_wallpaper': false,
              },
            }),
            200,
          );
        }
        if (path == '/v1/identity/consent') {
          return http.Response(jsonEncode({'consent': body}), 200);
        }
        if (path == '/v1/identity/pulse') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (path == '/v1/peers') {
          return http.Response(
            jsonEncode({
              'peers': [
                {
                  'account_id': 202,
                  'os': 'ios',
                  'os_expires': 9999999999,
                  'promax': true,
                  'allow_groups': false,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final client = HubClient(
        baseUri: Uri.parse('http://127.0.0.1:8091'),
        createClient: () => mock,
      );

      final config = await client.identityConfig();
      expect(config['ready'], isTrue);

      final session = await client.startIdentitySession('synthetic-proof');
      expect(session['token'], 'synthetic-token');

      final consent = await client.updateIdentityConsent(
        'synthetic-token',
        const HubConsent(showOs: true, showPromax: true),
      );
      expect(consent.showOs, isTrue);
      expect(consent.showPromax, isTrue);

      await client.sendPulse('synthetic-token', 'android');
      expect(recordedRequests['/v1/identity/pulse']?['body']?['os'], 'android');

      final peers = await client.queryPeers('synthetic-token', [202]);
      expect(peers.length, 1);
      expect(peers.first.accountId, 202);
      expect(peers.first.promax, isTrue);
      expect(peers.first.os, 'ios');

      await client.deleteIdentityMe('synthetic-token');
      expect(recordedRequests['/v1/identity/me']?['method'], 'DELETE');
    });
  });

  group('HubSocial service', () {
    test('changing visibility preserves unrelated server consents', () async {
      Map<String, dynamic>? update;
      final mock = MockClient((request) async {
        if (request.url.path == '/v1/identity/me') {
          return http.Response(
            jsonEncode({
              'consent': {
                'show_os': false,
                'show_promax': false,
                'allow_groups': true,
                'share_wallpaper': true,
              },
            }),
            200,
          );
        }
        if (request.url.path == '/v1/identity/consent') {
          update = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'consent': update}), 200);
        }
        return http.Response('{}', 200);
      });
      final social = HubSocial(client: HubClient(createClient: () => mock));
      await social.init(101, token: 'synthetic-token');
      await social.setShowPromax(true);
      expect(update?['allow_groups'], isTrue);
      expect(update?['share_wallpaper'], isTrue);
      social.dispose();
    });
    test('failed consent withdrawal leaves the saved state enabled', () async {
      var fail = false;
      final mock = MockClient((request) async {
        if (request.url.path == '/v1/identity/consent') {
          if (fail) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({'consent': jsonDecode(request.body)}),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final social = HubSocial(client: HubClient(createClient: () => mock));
      await social.init(101, token: 'synthetic-token');
      await social.setShowPromax(true);
      fail = true;
      await expectLater(social.setShowPromax(false), throwsA(isA<Exception>()));
      expect(social.showPromax, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(HubSocial.showPromaxKey(101)), isTrue);
      social.dispose();
    });

    test('failed deletion keeps credentials so it can be retried', () async {
      final mock = MockClient((request) async => http.Response('{}', 503));
      final social = HubSocial(client: HubClient(createClient: () => mock));
      await social.init(101, token: 'synthetic-token');
      await expectLater(social.deleteHubData(), throwsA(isA<Exception>()));
      expect(social.hasToken, isTrue);
      social.dispose();
    });

    test('a hidden peer disappears from the cache after refresh', () async {
      var visible = true;
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'peers': visible
                ? [
                    {'account_id': 303, 'promax': true},
                  ]
                : [],
          }),
          200,
        ),
      );
      final social = HubSocial(client: HubClient(createClient: () => mock));
      await social.init(101, token: 'synthetic-token');
      await social.queryPeers([303]);
      expect(social.hasProMaxBadge(303), isTrue);
      visible = false;
      await social.queryPeers([303]);
      expect(social.hasProMaxBadge(303), isFalse);
      social.dispose();
    });
    test('defaults to false and isolates state between accounts', () async {
      final social = HubSocial();
      await social.init(101);
      expect(social.showOs, isFalse);
      expect(social.showPromax, isFalse);
      expect(social.hasToken, isFalse);

      await social.setShowOs(true);
      await social.setShowPromax(true);
      expect(social.showOs, isTrue);
      expect(social.showPromax, isTrue);

      final secondAccountSocial = HubSocial();
      await secondAccountSocial.init(202);
      expect(secondAccountSocial.showOs, isFalse);
      expect(secondAccountSocial.showPromax, isFalse);

      social.dispose();
      secondAccountSocial.dispose();
    });

    test('pulse sends platform only when showOs is true', () async {
      var pulseCount = 0;
      final mock = MockClient((request) async {
        if (request.url.path == '/v1/identity/pulse') {
          pulseCount++;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('{}', 200);
      });

      final client = HubClient(
        baseUri: Uri.parse('http://127.0.0.1:8091'),
        createClient: () => mock,
      );
      final social = HubSocial(client: client);
      await social.init(101, token: 'synthetic-token');

      await social.pulse();
      expect(pulseCount, 0);

      await social.setShowOs(true);
      await social.pulse();
      expect(pulseCount, greaterThanOrEqualTo(1));

      social.dispose();
    });

    test('deleteHubData clears local state, preferences and token', () async {
      var deleteCalled = false;
      final mock = MockClient((request) async {
        if (request.url.path == '/v1/identity/me' &&
            request.method == 'DELETE') {
          deleteCalled = true;
          return http.Response(jsonEncode({'deleted': true}), 200);
        }
        return http.Response('{}', 200);
      });

      final client = HubClient(
        baseUri: Uri.parse('http://127.0.0.1:8091'),
        createClient: () => mock,
      );
      final social = HubSocial(client: client);
      await social.init(101, token: 'synthetic-token');
      await social.setShowOs(true);
      await social.setShowPromax(true);

      expect(social.showOs, isTrue);
      expect(social.showPromax, isTrue);

      await social.deleteHubData();
      expect(deleteCalled, isTrue);
      expect(social.showOs, isFalse);
      expect(social.showPromax, isFalse);
      expect(social.hasToken, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(HubSocial.showOsKey(101)), isNull);
      expect(prefs.getBool(HubSocial.showPromaxKey(101)), isNull);

      social.dispose();
    });

    test('queryPeers caches peer info and reports badge', () async {
      final mock = MockClient((request) async {
        if (request.url.path == '/v1/peers') {
          return http.Response(
            jsonEncode({
              'peers': [
                {
                  'account_id': 303,
                  'os': 'windows',
                  'os_expires': 9999999999,
                  'promax': true,
                  'allow_groups': false,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final client = HubClient(
        baseUri: Uri.parse('http://127.0.0.1:8091'),
        createClient: () => mock,
      );
      final social = HubSocial(client: client);
      await social.init(101, token: 'synthetic-token');

      final peers = await social.queryPeers([303]);
      expect(peers.length, 1);
      expect(social.hasProMaxBadge(303), isTrue);
      expect(social.hasProMaxBadge(999), isFalse);
      expect(social.getPeerOs(303), 'windows');

      social.dispose();
    });
  });
}
