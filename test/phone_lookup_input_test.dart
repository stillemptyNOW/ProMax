import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/countries.dart';
import 'package:promax/frontend/screens/contacts/phone_lookup_input.dart';

({CountryName country, String text}) _format(
  String text, {
  String country = 'RU',
  String previous = '',
}) {
  var selected = countriesByCode[country]!;
  final formatter = PhoneLookupInputFormatter(
    country: selected,
    onCountryChanged: (country) => selected = country,
  );
  final result = formatter.formatEditUpdate(
    TextEditingValue(text: previous),
    TextEditingValue(text: text),
  );
  return (country: selected, text: result.text);
}

void main() {
  test('formats a national number using the selected country', () {
    expect(_format('0000000000').text, '(000) 000-00-00');
  });

  test('pasting the full number does not duplicate its country code', () {
    final result = _format('+7 (000) 000-00-00');
    expect(result.country.code, 'RU');
    expect(result.text, '(000) 000-00-00');
  });

  test('a pasted international number selects its country', () {
    final result = _format('+1 (000) 000-0000');
    expect(result.country.code, 'US');
    expect(result.text, '(000) 000-0000');
  });

  test('a Russian national trunk prefix is not included in the subscriber', () {
    final result = _format('8 (400) 000-00-00');
    expect(result.country.code, 'RU');
    expect(result.text, '(400) 000-00-00');
  });

  test(
    'too many digits remain available for validation instead of truncating',
    () {
      expect(_format('00000000000').text, '00000000000');
    },
  );

  test('a shorter country mask never silently discards subscriber digits', () {
    final result = _format('0000000000', country: 'AT');
    expect(result.text.replaceAll(RegExp(r'\D'), ''), '0000000000');
  });

  test('letters cannot turn a pasted identifier into a phone number', () {
    expect(_format('user0000000000', previous: '(000)').text, '(000)');
  });

  test('unsupported international prefixes remain invalid input', () {
    expect(_format('+00000000000').text, '+00000000000');
  });
}
