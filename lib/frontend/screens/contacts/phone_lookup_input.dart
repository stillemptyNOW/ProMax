import 'package:flutter/services.dart';

import '../../../core/config/countries.dart';
import '../auth/phone_input_formatter.dart';

CountryName? _internationalCountry(String digits, CountryName country) {
  final matches = allCountries.where((candidate) {
    final prefix = candidate.phoneCode.substring(1);
    return digits.startsWith(prefix) &&
        digits.length == prefix.length + candidate.phoneDigits;
  }).toList();
  matches.sort((a, b) {
    if (a.code == country.code) return -1;
    if (b.code == country.code) return 1;
    final byLength = b.phoneCode.length.compareTo(a.phoneCode.length);
    if (byLength != 0) return byLength;
    return (isPrimaryForPhoneCode(b) ? 1 : 0).compareTo(
      isPrimaryForPhoneCode(a) ? 1 : 0,
    );
  });
  return matches.firstOrNull;
}

String? phoneLookupNumber(String text, CountryName country) {
  final raw = text.trim();
  if (!RegExp(r'^\+?[\d\s().-]*$').hasMatch(raw)) return null;
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+')) {
    final matched = _internationalCountry(digits, country);
    if (matched == null || digits.length > 15) return null;
    return '+$digits';
  }
  if (country.phoneCode == '+7' &&
      digits.length == country.phoneDigits + 1 &&
      (digits.startsWith('8') || digits.startsWith('7'))) {
    digits = digits.substring(1);
  }
  final phone = '${country.phoneCode}$digits';
  return digits.length == country.phoneDigits && phone.length <= 16
      ? phone
      : null;
}

class PhoneLookupInputFormatter extends TextInputFormatter {
  final CountryName country;
  final ValueChanged<CountryName> onCountryChanged;

  PhoneLookupInputFormatter({
    required this.country,
    required this.onCountryChanged,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.trim();
    if (!RegExp(r'^\+?[\d\s().-]*$').hasMatch(raw)) return oldValue;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (raw.startsWith('+')) {
      final matched = _internationalCountry(digits, country);
      if (matched != null && matched.code != country.code) {
        onCountryChanged(matched);
      }
      return newValue;
    }
    final maskDigits = country.phoneGroupSizes.fold<int>(0, (a, b) => a + b);
    if (digits.length > country.phoneDigits || digits.length > maskDigits) {
      return newValue;
    }
    return PhoneInputFormatter(country).formatEditUpdate(oldValue, newValue);
  }
}
