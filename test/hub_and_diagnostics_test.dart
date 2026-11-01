import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:promax/core/hub/diagnostics.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/core/hub/hub_inbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends HubClient {
  List<HubMessage> feed = const [];
  bool fail = false;
  final uploads = <Map<String, dynamic>>[];
  @override
  Future<List<HubMessage>> messages() async {
    if (fail) throw const HubException(503);
    return feed;
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? token,
  }) async {
    uploads.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    return {'accepted': 1};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Synthetic',
      packageName: 'test.synthetic',
      version: '0.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(Diagnostics.dispose);

  test('service chat persists messages and read state by account', () async {
    final client = _Client()
      ..feed = const [
        HubMessage(id: 1, text: 'synthetic announcement', created: 100),
      ];
    final inbox = HubInbox(accountId: 101, phone: 11112223344, client: client);
    await inbox.init();
    expect(inbox.unread, 1);
    await inbox.markRead();
    expect(inbox.unread, 0);
    inbox.dispose();
    client.fail = true;
    final restored = HubInbox(
      accountId: 101,
      phone: 11112223344,
      client: client,
    );
    await restored.init();
    expect(restored.messages.single.text, 'synthetic announcement');
    expect(restored.unread, 0);
    expect(restored.offline, isTrue);
    restored.dispose();
    final other = HubInbox(accountId: 202, phone: 11112223345, client: client);
    await other.init();
    expect(other.messages, isEmpty);
    other.dispose();
  });

  test('repeated polling never duplicates announcements', () async {
    final client = _Client()
      ..feed = const [HubMessage(id: 1, text: 'synthetic', created: 100)];
    final inbox = HubInbox(accountId: 101, phone: 11112223344, client: client);
    addTearDown(inbox.dispose);
    await inbox.init();
    await inbox.refresh();
    expect(inbox.messages.length, 1);
    expect(inbox.adminCandidate, isFalse);
    expect(
      () => inbox.activate('synthetic-code'),
      throwsA(isA<HubException>()),
    );
  });

  test(
    'diagnostics contain no exception message, phone, token or local path',
    () async {
      final client = _Client();
      await Diagnostics.init(client: client);
      Diagnostics.record(
        'flutter_error',
        StateError('synthetic private body token=synthetic-secret'),
        StackTrace.fromString(
          '#0 synthetic (package:promax/main.dart:12:3)\n'
          '#1 native (/home/synthetic-user/private.dart:9:2)',
        ),
      );
      await Diagnostics.flush();
      final upload = client.uploads.single;
      final event = (upload['events'] as List).single as Map;
      expect(event.keys.toSet(), {
        'kind',
        'error_type',
        'frames',
        'version',
        'platform',
      });
      expect(event['frames'], ['package:promax/main.dart:12:3']);
      expect(jsonEncode(upload), isNot(contains('synthetic-secret')));
      expect(jsonEncode(upload), isNot(contains('synthetic-user')));
    },
  );

  test(
    'disabling diagnostics drops the queued data and prevents uploads',
    () async {
      final client = _Client();
      await Diagnostics.init(client: client);
      Diagnostics.record(
        'log_error',
        StateError('synthetic'),
        StackTrace.current,
      );
      await Diagnostics.setEnabled(false);
      await Diagnostics.flush();
      Diagnostics.record(
        'log_error',
        StateError('synthetic'),
        StackTrace.current,
      );
      await Diagnostics.flush();
      expect(client.uploads, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(Diagnostics.enabledKey), isFalse);
      expect(prefs.getString('promax_diagnostics_queue'), isNull);
    },
  );

  test('restored diagnostics strip unknown fields before sending', () async {
    SharedPreferences.setMockInitialValues({
      'promax_diagnostics_queue': jsonEncode([
        {
          'kind': 'flutter_error',
          'error_type': 'StateError',
          'version': '0.0.0',
          'platform': 'android',
          'frames': ['package:promax/main.dart:12:3'],
          'text': 'synthetic private body',
        },
      ]),
    });
    final client = _Client();
    await Diagnostics.init(client: client);
    await Diagnostics.flush();
    expect(
      jsonEncode(client.uploads),
      isNot(contains('synthetic private body')),
    );
  });
  test(
    'hub HTTP client sends JSON and bearer token without following redirects',
    () async {
      late http.Request captured;
      final client = HubClient(
        createClient: () => MockClient((request) async {
          captured = request;
          return http.Response(
            '{"accepted":1}',
            202,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.request(
        '/v1/telemetry',
        method: 'POST',
        token: 'synthetic-token',
        body: {'synthetic': true},
      );
      expect(captured.headers['Authorization'], 'Bearer synthetic-token');
      expect(captured.followRedirects, isFalse);
      expect(jsonDecode(captured.body), {'synthetic': true});
    },
  );
}
