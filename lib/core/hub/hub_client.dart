import 'dart:convert';
import 'package:http/http.dart' as http;

class HubException implements Exception {
  const HubException(this.status);
  final int status;
}

class HubMessage {
  const HubMessage({
    required this.id,
    required this.text,
    required this.created,
  });
  final int id;
  final String text;
  final int created;
  factory HubMessage.fromJson(Map<String, dynamic> value) => HubMessage(
    id: value['id'] as int,
    text: value['text'] as String,
    created: value['created'] as int,
  );
  Map<String, Object> toJson() => {'id': id, 'text': text, 'created': created};
}

class HubDraft {
  const HubDraft({
    required this.text,
    required this.revision,
    required this.publishedRevision,
  });
  final String text;
  final int revision;
  final int publishedRevision;
  factory HubDraft.fromJson(Map<String, dynamic> value) => HubDraft(
    text: value['text'] as String,
    revision: value['revision'] as int,
    publishedRevision: value['published_revision'] as int,
  );
}

class HubClient {
  HubClient({Uri? baseUri, http.Client Function()? createClient})
    : baseUri = baseUri ?? Uri.parse('https://boriskino.qd.je/'),
      _createClient = createClient ?? http.Client.new;
  final Uri baseUri;
  final http.Client Function() _createClient;
  final Set<http.Client> _active = {};
  void cancel() {
    for (final client in _active) {
      client.close();
    }
    _active.clear();
  }

  static const timeout = Duration(seconds: 12);

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? token,
  }) async {
    final client = _createClient();
    _active.add(client);
    try {
      final request = http.Request(method, baseUri.resolve(path))
        ..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HubException(response.statusCode);
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) throw const HubException(413);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) throw const HubException(502);
      return decoded;
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  Future<List<HubMessage>> messages() async {
    final response = await request('/v1/announcements');
    return [
      for (final raw in response['messages'] as List)
        HubMessage.fromJson(raw as Map<String, dynamic>),
    ];
  }

  Future<String> activate(String code, int accountId) async {
    final response = await request(
      '/v1/admin/pair',
      method: 'POST',
      body: {'code': code.trim(), 'account_id': accountId},
    );
    return response['token'] as String;
  }

  Future<HubDraft> draft(String token) async =>
      HubDraft.fromJson(await request('/v1/admin/draft', token: token));

  Future<HubDraft> saveDraft(String token, String text, int revision) async =>
      HubDraft.fromJson(
        await request(
          '/v1/admin/draft',
          token: token,
          method: 'PUT',
          body: {'text': text, 'revision': revision},
        ),
      );

  Future<void> publish(String token, int revision) async {
    await request(
      '/v1/admin/publish',
      token: token,
      method: 'POST',
      body: {'revision': revision},
    );
  }
}
