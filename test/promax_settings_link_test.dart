import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promax/core/config/promax_settings_link.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/frontend/screens/profile/settings_link_import.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _rawLink(Object value) =>
    'https://boriskino.qd.je/settings#v1.${base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '')}';

const _shortCode = 'Abcdef0123456789_-abcd';
const _shortLink = 'https://proma-x.xyz/s#$_shortCode';

HubClient _testHub(Future<http.Response> Function(http.Request) handler) =>
    HubClient(createClient: () => MockClient(handler));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new links use product domain and old links remain importable', () {
    final settings = <String, Object>{'app_amoled': true};
    final link = ProMaxSettingsLink.encode(settings);
    expect(Uri.parse(link).host, 'proma-x.xyz');
    expect(ProMaxSettingsLink.decode(link)['settings'], settings);
    final legacy = link.replaceFirst('proma-x.xyz', 'boriskino.qd.je');
    expect(ProMaxSettingsLink.decode(legacy)['settings'], settings);
  });

  test(
    'settings round trip through HTTPS and native links without a server',
    () {
      final settings = <String, Object>{
        'app_amoled': true,
        'app_font_scale': 1.2,
        'promax_quick_reaction': '🌟',
      };
      final link = ProMaxSettingsLink.encode(settings);
      final uri = Uri.parse(link);
      expect(uri.query, isEmpty);
      expect(uri.path, '/settings');
      expect(ProMaxSettingsLink.decode(link)['settings'], settings);
      expect(
        ProMaxSettingsLink.decode(
          'promax://settings#${uri.fragment}',
        )['settings'],
        settings,
      );
    },
  );

  test(
    'export excludes credentials, account IDs and deleted history',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth_token_101': 'synthetic-token',
        'promax_backup_key_101': 'synthetic-recovery',
        'promax_hub_admin_token_101': 'synthetic-admin',
        'deleted': 'synthetic-private-history',
        'app_amoled': true,
      });
      final link = await ProMaxSettingsLink.export(
        hub: _testHub((_) async => http.Response('', 503)),
      );
      final data = ProMaxSettingsLink.decode(link);
      expect(
        data.keys,
        unorderedEquals([
          'format',
          'version',
          'settings',
          'platform',
          'platformSettings',
        ]),
      );
      expect(data['settings']['app_amoled'], true);
      expect(jsonEncode(data), isNot(contains('synthetic-')));
    },
  );

  test(
    'exports and resolves a short link with only allowed settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_amoled': true,
        'auth_token_101': 'synthetic-token',
      });
      Object? exported;
      final hub = _testHub((request) async {
        expect(request.url.host, 'proma-x.xyz');
        if (request.method == 'POST') {
          expect(request.url.path, '/v1/settings-links');
          expect(request.body, isNot(contains('synthetic-token')));
          exported = jsonDecode(request.body);
          return http.Response(jsonEncode({'code': _shortCode}), 201);
        }
        expect(request.url.path, '/v1/settings-links/$_shortCode');
        return http.Response.bytes(utf8.encode(jsonEncode(exported)), 200);
      });
      final link = await ProMaxSettingsLink.export(hub: hub);
      expect(link, _shortLink);
      expect(link.length, lessThan(50));
      expect(ProMaxSettingsLink.matches(Uri.parse(link)), isTrue);
      for (final opened in [link, 'promax://settings#v2.$_shortCode']) {
        final data = await ProMaxSettingsLink.resolve(opened, hub: hub);
        expect(data['settings']['app_amoled'], true);
      }
    },
  );

  test('rejects unknown short links and unsafe Hub documents', () async {
    for (final response in [
      http.Response('', 404),
      http.Response(
        jsonEncode({
          'format': 'ProMax',
          'version': 1,
          'settings': {'app_amoled': true},
          'deleted': {'ciphertext': 'synthetic'},
        }),
        200,
      ),
    ]) {
      await expectLater(
        ProMaxSettingsLink.resolve(
          _shortLink,
          hub: _testHub((_) async => response),
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed short links without contacting the Hub', () async {
    final hub = _testHub((_) async => throw StateError('Unexpected request'));
    for (final link in [
      'https://proma-x.xyz/s#too-short',
      'https://proma-x.xyz/s?x=1#$_shortCode',
      'https://synthetic.example/s#$_shortCode',
    ]) {
      await expectLater(
        ProMaxSettingsLink.resolve(link, hub: hub),
        throwsFormatException,
      );
    }
  });

  test(
    'rejects unknown, out of range and account payloads before applying',
    () {
      for (final data in [
        {
          'format': 'ProMax',
          'version': 1,
          'settings': {'auth_token_101': 'synthetic'},
        },
        {
          'format': 'ProMax',
          'version': 1,
          'settings': {'app_font_scale': 100},
        },
        {
          'format': 'ProMax',
          'version': 2,
          'settings': {'app_amoled': true},
        },
        {
          'format': 'ProMax',
          'version': 1,
          'settings': {'app_amoled': true},
          'deleted': {},
        },
        {'format': 'ProMax', 'version': 1, 'settings': {}},
        [],
      ]) {
        expect(
          () => ProMaxSettingsLink.decode(_rawLink(data)),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects lookalike origins, malformed and oversized links', () {
    final valid = ProMaxSettingsLink.encode({'app_amoled': true});
    for (final link in [
      valid.replaceFirst('proma-x.xyz', 'synthetic.example'),
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('/settings#', '/settings?unexpected=1#'),
      valid.replaceFirst('v1.', 'v2.'),
      'https://boriskino.qd.je/settings#v1.%',
      'https://boriskino.qd.je/settings#v1.${'a' * ProMaxSettingsLink.maxLength}',
    ]) {
      expect(() => ProMaxSettingsLink.decode(link), throwsFormatException);
    }
  });

  testWidgets(
    'opening a link requires confirmation and cancel changes nothing',
    (tester) async {
      final link = ProMaxSettingsLink.encode({'app_amoled': true});
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => importProMaxSettingsLink(context, link),
                child: const Text('Open synthetic settings'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open synthetic settings'));
      await tester.pumpAndSettle();
      expect(find.text('ProMax settings link'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_amoled'), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('app_amoled'), isNull);
    },
  );
}
