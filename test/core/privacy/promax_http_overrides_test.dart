import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/privacy_settings.dart';
import 'package:promax/core/transport/promax_http_overrides.dart';

void main() {
  tearDown(() => HttpOverrides.global = null);

  test('сертификат Минцифры применяется только к хостам MAX', () {
    ProMaxHttpOverrides.install(trustMincifryForMaxHosts: true);
    expect(
      ProMaxHttpOverrides.usesMincifryFor(Uri.parse('https://api.oneme.ru/')),
      isTrue,
    );
    expect(
      ProMaxHttpOverrides.usesMincifryFor(Uri.parse('https://api.github.com/')),
      isFalse,
    );
    expect(
      ProMaxHttpOverrides.usesMincifryFor(Uri.parse('http://api.oneme.ru/')),
      isFalse,
    );
  });

  test('без доверия Минцифры не применяется нигде', () {
    ProMaxHttpOverrides.install(trustMincifryForMaxHosts: false);
    expect(
      ProMaxHttpOverrides.usesMincifryFor(Uri.parse('https://api.oneme.ru/')),
      isFalse,
    );
  });

  test('HTTP-клиенты получают нейтральный User-Agent вместо Dart', () {
    ProMaxHttpOverrides.install(trustMincifryForMaxHosts: false);
    final client = HttpClient();
    addTearDown(client.close);
    expect(client.userAgent, PrivacySettings.cdnUserAgent);
    expect(client.userAgent, isNot(contains('Dart')));
  });
}
