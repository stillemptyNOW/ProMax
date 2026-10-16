import 'dart:convert';
import 'dart:io';

import '../config/privacy_settings.dart';
import '../privacy/host_policy.dart';
import 'mincifry_ca.dart';

class ProMaxHttpOverrides extends HttpOverrides {
  ProMaxHttpOverrides._();

  static final ProMaxHttpOverrides _instance = ProMaxHttpOverrides._();
  static bool _trustMincifryForMaxHosts = false;

  static final SecurityContext _mincifryContext = SecurityContext(
    withTrustedRoots: true,
  )..setTrustedCertificatesBytes(utf8.encode(mincifryCaPem));

  static void install({required bool trustMincifryForMaxHosts}) {
    _trustMincifryForMaxHosts = trustMincifryForMaxHosts;
    HttpOverrides.global = _instance;
  }

  static bool usesMincifryFor(Uri uri) =>
      _trustMincifryForMaxHosts &&
      uri.isScheme('https') &&
      HostPolicy.trustsMincifryCa(uri.host);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..userAgent = PrivacySettings.cdnUserAgent;
    if (context == null) client.connectionFactory = _connect;
    return client;
  }

  static Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) {
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }
    if (!uri.isScheme('https')) return Socket.startConnect(uri.host, uri.port);
    return SecureSocket.startConnect(
      uri.host,
      uri.port,
      context: usesMincifryFor(uri) ? _mincifryContext : null,
    );
  }
}
