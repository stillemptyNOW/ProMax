import 'dart:convert';

import '../hub/hub_client.dart';
import 'product_links.dart';
import 'promax_archive.dart';

class ProMaxSettingsLink {
  static const maxLength = 16384;
  static const _prefix = '${ProductLinks.website}settings#v1.';
  static const _shortPrefix = '${ProductLinks.website}s#';
  static const _endpoint = '/v1/settings-links';
  static final _codePattern = RegExp(r'^[A-Za-z0-9_-]{22}$');
  static final _hub = HubClient(
    maxResponseBytes: maxLength,
    requestTimeout: const Duration(seconds: 4),
  );

  static bool matches(Uri uri) =>
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      ((uri.scheme == 'https' &&
              {'proma-x.xyz', 'boriskino.qd.je'}.contains(uri.host) &&
              uri.port == 443 &&
              (uri.path == '/settings' || uri.path == '/s')) ||
          (uri.scheme == 'promax' &&
              uri.host == 'settings' &&
              !uri.hasPort &&
              uri.path.isEmpty));

  static Future<String> export({HubClient? hub}) async {
    final data = await ProMaxArchive.settingsDocument();
    final portable = _encodeDocument(data);
    try {
      final response = await (hub ?? _hub).request(
        _endpoint,
        method: 'POST',
        body: data,
      );
      final code = response['code'];
      if (code is String && _codePattern.hasMatch(code)) {
        return '$_shortPrefix$code';
      }
    } on Exception {
      return portable;
    }
    return portable;
  }

  static Future<Map<String, dynamic>> resolve(
    String link, {
    HubClient? hub,
  }) async {
    final uri = _parse(link);
    final String code;
    if (uri.path == '/s') {
      code = uri.fragment;
    } else if (uri.scheme == 'promax' && uri.fragment.startsWith('v2.')) {
      code = uri.fragment.substring(3);
    } else {
      return _decodePortable(uri);
    }
    if (!_codePattern.hasMatch(code)) {
      throw const FormatException('Invalid settings link');
    }
    try {
      return _validate(await (hub ?? _hub).request('$_endpoint/$code'));
    } on HubException catch (error) {
      if (error.status == 404) {
        throw const FormatException('Unknown or expired settings link');
      }
      rethrow;
    }
  }

  static String encode(Map<String, Object> settings) {
    return _encodeDocument({
      'format': 'ProMax',
      'version': 1,
      'settings': settings,
    });
  }

  static String _encodeDocument(Map<String, dynamic> document) {
    final data = _validate(document);
    final payload = base64Url
        .encode(utf8.encode(jsonEncode(data)))
        .replaceAll('=', '');
    final link = '$_prefix$payload';
    if (link.length > maxLength) {
      throw const FormatException('Settings link is too large');
    }
    return link;
  }

  static Map<String, dynamic> decode(String link) =>
      _decodePortable(_parse(link));

  static Uri _parse(String link) {
    if (link.length > maxLength) {
      throw const FormatException('Settings link is too large');
    }
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !matches(uri)) {
      throw const FormatException('Unsupported settings link');
    }
    return uri;
  }

  static Map<String, dynamic> _decodePortable(Uri uri) {
    if (uri.path == '/s' || !uri.fragment.startsWith('v1.')) {
      throw const FormatException('Unsupported settings link');
    }
    final payload = uri.fragment.substring(3);
    if (payload.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload)) {
      throw const FormatException('Invalid settings link');
    }
    return _validate(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload)))),
    );
  }

  static Map<String, dynamic> _validate(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) => !{
            'format',
            'version',
            'settings',
            'platform',
            'platformSettings',
          }.contains(key),
        ) ||
        value['format'] != 'ProMax' ||
        value['version'] != 1 ||
        value['settings'] is! Map) {
      throw const FormatException('Invalid settings link');
    }
    final settings = value['settings'] as Map;
    if (settings.isEmpty ||
        settings.entries.any(
          (entry) =>
              entry.key is! String ||
              !ProMaxArchive.validSetting(entry.key as String, entry.value),
        )) {
      throw const FormatException('Invalid settings in link');
    }
    return ProMaxArchive.decode(utf8.encode(jsonEncode(value)));
  }
}
