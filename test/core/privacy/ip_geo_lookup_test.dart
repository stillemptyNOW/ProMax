import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/privacy/ip_geo_lookup.dart';

void main() {
  test('запрос идёт только по HTTPS', () {
    final uri = IpGeoLookup.uriFor('203.0.113.7');
    expect(uri.scheme, 'https');
    expect(uri.host, IpGeoLookup.serviceHost);
    expect(uri.path, '/203.0.113.7');
  });

  test('из строки места берётся публичный IPv4', () {
    expect(IpGeoLookup.extractIpv4('Город, 198.51.100.23'), '198.51.100.23');
    expect(IpGeoLookup.extractIpv4('нет адреса'), isNull);
    expect(IpGeoLookup.extractIpv4('999.1.1.1'), isNull);
  });

  test('локальные и служебные адреса никуда не отправляются', () {
    for (final ip in [
      '10.0.0.1',
      '127.0.0.1',
      '172.16.5.4',
      '192.168.1.10',
      '169.254.0.3',
      '100.64.0.1',
      '0.0.0.0',
      '224.0.0.1',
    ]) {
      expect(IpGeoLookup.extractIpv4(ip), isNull, reason: ip);
    }
  });

  test('ответ сервиса приводится к полям экрана устройств', () {
    final parsed = IpGeoLookup.parse({
      'success': true,
      'country': 'Synthetic Country',
      'city': 'Synthetic City',
      'connection': {'asn': 64500, 'org': 'Example Org', 'isp': 'Example ISP'},
      'timezone': {'id': 'Etc/UTC'},
    });
    expect(parsed, {
      'country': 'Synthetic Country',
      'city': 'Synthetic City',
      'isp': 'Example ISP',
      'as': 'AS64500 Example Org',
      'timezone': 'Etc/UTC',
    });
  });

  test('ошибка сервиса не превращается в данные', () {
    expect(IpGeoLookup.parse({'success': false, 'message': 'x'}), isNull);
    expect(IpGeoLookup.parse('oops'), isNull);
    expect(IpGeoLookup.parse({'success': true})?['as'], isNull);
  });
}
