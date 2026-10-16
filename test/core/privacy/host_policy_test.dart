import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/privacy/host_policy.dart';

void main() {
  group('Минцифры доверяем только для MAX и Госуслуг', () {
    test('хосты MAX и Госуслуг', () {
      expect(HostPolicy.trustsMincifryCa('api.oneme.ru'), isTrue);
      expect(HostPolicy.trustsMincifryCa('ext-api.max.ru'), isTrue);
      expect(HostPolicy.trustsMincifryCa('i.okcdn.ru'), isTrue);
      expect(HostPolicy.trustsMincifryCa('esia.gosuslugi.ru'), isTrue);
      expect(HostPolicy.trustsMincifryCa('MAX.RU.'), isTrue);
    });

    test('посторонние и похожие хосты', () {
      expect(HostPolicy.trustsMincifryCa('api.github.com'), isFalse);
      expect(HostPolicy.trustsMincifryCa('fonts.googleapis.com'), isFalse);
      expect(HostPolicy.trustsMincifryCa('notmax.ru'), isFalse);
      expect(HostPolicy.trustsMincifryCa('max.ru.example.org'), isFalse);
      expect(HostPolicy.trustsMincifryCa(''), isFalse);
    });
  });

  group('трекеры', () {
    test('домены из списка и их поддомены', () {
      expect(
        HostPolicy.isTracker(Uri.parse('https://top-fwz1.mail.ru/counter')),
        isTrue,
      );
      expect(
        HostPolicy.isTracker(Uri.parse('https://mc.yandex.ru/watch/1')),
        isTrue,
      );
      expect(
        HostPolicy.isTracker(
          Uri.parse('https://www.google-analytics.com/g/collect'),
        ),
        isTrue,
      );
    });

    test('обычные хосты не блокируются', () {
      expect(HostPolicy.isTracker(Uri.parse('https://mail.ru/')), isFalse);
      expect(
        HostPolicy.isTracker(Uri.parse('https://yandex.ru/maps')),
        isFalse,
      );
      expect(HostPolicy.isTracker(Uri.parse('https://max.ru/app')), isFalse);
      expect(HostPolicy.isTracker(Uri.parse('data:text/plain,1')), isFalse);
    });

    test('фильтры блокировщика совпадают с URL целиком', () {
      final filter = RegExp(
        HostPolicy.trackerUrlFilter('mc.yandex.ru'),
        caseSensitive: false,
      );
      bool matches(String url) => filter.matchAsPrefix(url)?.end == url.length;
      expect(matches('https://mc.yandex.ru/watch/1?x=1'), isTrue);
      expect(matches('https://mc.yandex.ru'), isTrue);
      expect(matches('https://cdn.mc.yandex.ru:443/tag.js'), isTrue);
      expect(matches('https://mc.yandex.ru.example.org/'), isFalse);
      expect(matches('https://notmc.yandex.ru/'), isFalse);
      expect(
        HostPolicy.trackerUrlFilters(),
        hasLength(HostPolicy.trackerDomains.length),
      );
    });
  });

  group('нативный fetch Цифрового ID', () {
    test('разрешены только https-хосты MAX и Госуслуг', () {
      expect(
        HostPolicy.allowsMobileIdFetch(
          Uri.parse('https://id.gosuslugi.ru/check'),
        ),
        isTrue,
      );
      expect(
        HostPolicy.allowsMobileIdFetch(Uri.parse('https://ext-api.max.ru/v')),
        isTrue,
      );
    });

    test('чужие хосты, IP, порты, http и userinfo запрещены', () {
      for (final url in [
        'https://example.org/',
        'http://id.gosuslugi.ru/',
        'https://192.0.2.10/',
        'https://[2001:db8::1]/',
        'https://max.ru:8443/',
        'https://user@max.ru/',
        'https://max.ru.example.org/',
      ]) {
        expect(HostPolicy.allowsMobileIdFetch(Uri.parse(url)), isFalse);
      }
    });
  });

  group('изоляция мини-приложений', () {
    test('Цифровой ID и Госуслуги сохраняют данные', () {
      expect(HostPolicy.isPersistentWebHost('digital-id.max.ru'), isTrue);
      expect(HostPolicy.isPersistentWebHost('esia.gosuslugi.ru'), isTrue);
      expect(HostPolicy.isPersistentWebHost('game.example.org'), isFalse);
    });

    test('куки чистятся по хосту и родителям, кроме общих с Цифровым ID', () {
      expect(HostPolicy.cookieDomainsToClear('a.b.example.org'), [
        'a.b.example.org',
        'b.example.org',
        'example.org',
      ]);
      expect(HostPolicy.cookieDomainsToClear('game.max.ru'), ['game.max.ru']);
      expect(HostPolicy.cookieDomainsToClear('digital-id.max.ru'), isEmpty);
      expect(HostPolicy.cookieDomainsToClear('203.0.113.7'), isEmpty);
    });
  });
}
