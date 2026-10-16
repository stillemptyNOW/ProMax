abstract final class IpGeoLookup {
  static const String serviceHost = 'ipwho.is';

  static final RegExp _ipv4 = RegExp(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b');

  static String? extractIpv4(String text) {
    final match = _ipv4.firstMatch(text)?.group(0);
    if (match == null) return null;
    final octets = match.split('.').map(int.parse).toList();
    if (octets.any((octet) => octet > 255)) return null;
    if (_isNonPublic(octets)) return null;
    return match;
  }

  static Uri uriFor(String ip) => Uri.https(serviceHost, '/$ip');

  static Map<String, dynamic>? parse(Object? body) {
    if (body is! Map) return null;
    if (body['success'] != true) return null;
    final connection = body['connection'];
    final timezone = body['timezone'];
    final asn = connection is Map ? connection['asn'] : null;
    final org = connection is Map ? connection['org'] : null;
    final network = [
      if (asn != null) 'AS$asn',
      if (org is String && org.isNotEmpty) org,
    ].join(' ');
    return {
      'country': body['country'],
      'city': body['city'],
      'isp': connection is Map ? connection['isp'] : null,
      'as': network.isEmpty ? null : network,
      'timezone': timezone is Map ? timezone['id'] : null,
    };
  }

  static bool _isNonPublic(List<int> o) =>
      o[0] == 0 ||
      o[0] == 10 ||
      o[0] == 127 ||
      o[0] >= 224 ||
      (o[0] == 100 && o[1] >= 64 && o[1] <= 127) ||
      (o[0] == 169 && o[1] == 254) ||
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] == 192 && o[1] == 168);
}
