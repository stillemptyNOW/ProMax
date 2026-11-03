import 'dart:convert';

import 'promax_archive.dart';

class ProMaxSettingsLink {
  static const maxLength = 16384;
  static const _prefix = 'https://proma-x.xyz/settings#v1.';

  static bool matches(Uri uri) =>
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      ((uri.scheme == 'https' &&
              {'proma-x.xyz', 'boriskino.qd.je'}.contains(uri.host) &&
              uri.port == 443 &&
              uri.path == '/settings') ||
          (uri.scheme == 'promax' &&
              uri.host == 'settings' &&
              !uri.hasPort &&
              uri.path.isEmpty));

  static Future<String> export() async =>
      _encodeDocument(await ProMaxArchive.settingsDocument());

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

  static Map<String, dynamic> decode(String link) {
    if (link.length > maxLength) {
      throw const FormatException('Settings link is too large');
    }
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !matches(uri) || !uri.fragment.startsWith('v1.')) {
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
