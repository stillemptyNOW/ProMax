import '../../../core/security/url_policy.dart';

const Set<String> _firstPartyDomains = {'max.ru', 'oneme.ru'};

class WebAppOriginPolicy {
  WebAppOriginPolicy(Uri launch) {
    trust(launch);
  }

  final Set<String> _trusted = {};
  final Set<String> _visited = {};
  bool _firstParty = false;

  static bool isFirstPartyHost(String host) {
    final lower = host.toLowerCase();
    return _firstPartyDomains.any(
      (domain) => lower == domain || lower.endsWith('.$domain'),
    );
  }

  void trust(Uri uri) {
    final origin = webOriginOf(uri);
    if (origin == null) return;
    _trusted.add(origin);
    if (_isSecureFirstParty(uri)) _firstParty = true;
  }

  void allowVisit(Uri uri) {
    final origin = webOriginOf(uri);
    if (origin != null) _visited.add(origin);
  }

  bool trusts(Uri? uri) {
    final origin = webOriginOf(uri);
    if (origin == null) return false;
    if (_trusted.contains(origin)) return true;
    return _firstParty && _isSecureFirstParty(uri!);
  }

  bool mayNavigate(Uri? uri) =>
      trusts(uri) || _visited.contains(webOriginOf(uri));

  static bool _isSecureFirstParty(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' && isFirstPartyHost(uri.host);
}
