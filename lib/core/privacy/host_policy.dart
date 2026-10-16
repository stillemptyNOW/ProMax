abstract final class HostPolicy {
  static const List<String> maxDomains = [
    'max.ru',
    'oneme.ru',
    'okcdn.ru',
    'mycdn.me',
    'vkuser.net',
    'userapi.com',
  ];

  static const List<String> gosuslugiDomains = ['gosuslugi.ru'];

  static const List<String> mobileIdDomains = [
    'max.ru',
    'oneme.ru',
    'gosuslugi.ru',
  ];

  static const List<String> persistentWebDomains = [
    'digital-id.max.ru',
    'gosuslugi.ru',
  ];

  static const List<String> trackerDomains = [
    'top-fwz1.mail.ru',
    'mytracker.ru',
    'mc.yandex.ru',
    'mc.yandex.com',
    'an.yandex.ru',
    'counter.yadro.ru',
    'tns-counter.ru',
    'google-analytics.com',
    'analytics.google.com',
    'googletagmanager.com',
    'doubleclick.net',
    'googlesyndication.com',
    'connect.facebook.net',
    'sentry.io',
    'amplitude.com',
    'mixpanel.com',
    'hotjar.com',
    'clarity.ms',
  ];

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

  static String normalize(String host) {
    var normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool matchesAny(String host, Iterable<String> domains) {
    final normalized = normalize(host);
    if (normalized.isEmpty) return false;
    for (final domain in domains) {
      if (normalized == domain || normalized.endsWith('.$domain')) return true;
    }
    return false;
  }

  static bool isIpLiteral(String host) {
    final normalized = normalize(host);
    return _ipv4.hasMatch(normalized) || normalized.contains(':');
  }

  static bool isMaxHost(String host) => matchesAny(host, maxDomains);

  static bool trustsMincifryCa(String host) =>
      matchesAny(host, maxDomains) || matchesAny(host, gosuslugiDomains);

  static bool isPersistentWebHost(String host) =>
      matchesAny(host, persistentWebDomains);

  static bool isTracker(Uri uri) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
    return matchesAny(uri.host, trackerDomains);
  }

  static bool allowsMobileIdFetch(Uri uri) {
    if (!uri.isScheme('https')) return false;
    if (uri.userInfo.isNotEmpty) return false;
    if (uri.hasPort && uri.port != 443) return false;
    final host = normalize(uri.host);
    if (host.isEmpty || isIpLiteral(host)) return false;
    return matchesAny(host, mobileIdDomains);
  }

  static String trackerUrlFilter(String domain) {
    final escaped = domain.replaceAll('.', r'\.');
    return '^https?://([a-z0-9-]+\\.)*$escaped([/:?#].*)?\$';
  }

  static List<String> trackerUrlFilters() => [
    for (final domain in trackerDomains) trackerUrlFilter(domain),
  ];

  static List<String> cookieDomainsToClear(String host) {
    final normalized = normalize(host);
    if (normalized.isEmpty || isIpLiteral(normalized)) return const [];
    if (isPersistentWebHost(normalized)) return const [];
    final labels = normalized.split('.');
    final domains = <String>[];
    for (var start = 0; start <= labels.length - 2; start++) {
      final domain = labels.sublist(start).join('.');
      if (_sharesCookiesWithPersistentHost(domain)) continue;
      domains.add(domain);
    }
    return domains;
  }

  static bool _sharesCookiesWithPersistentHost(String domain) =>
      persistentWebDomains.any(
        (persistent) => persistent == domain || persistent.endsWith('.$domain'),
      ) ||
      isPersistentWebHost(domain);
}
