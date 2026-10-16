const Set<String> appLinkSchemes = {'promax', 'max'};

const Set<String> _webSchemes = {'http', 'https'};

const Set<String> _contactSchemes = {'mailto', 'tel', 'sms'};

bool isAppLinkUri(Uri uri) => appLinkSchemes.contains(uri.scheme.toLowerCase());

bool isWebUri(Uri uri) =>
    _webSchemes.contains(uri.scheme.toLowerCase()) && uri.host.isNotEmpty;

bool isAllowedExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (_webSchemes.contains(scheme)) return isWebUri(uri);
  if (!_contactSchemes.contains(scheme)) return false;
  return !uri.hasAuthority && (uri.path.isNotEmpty || uri.hasQuery);
}

Uri? parseExternalUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !isAllowedExternalUri(uri)) return null;
  return uri;
}

String? webOriginOf(Uri? uri) {
  if (uri == null || !isWebUri(uri)) return null;
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}';
}
