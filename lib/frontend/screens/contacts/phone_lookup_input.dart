import 'package:flutter/services.dart';

import '../../../core/config/countries.dart';
import '../auth/phone_input_formatter.dart';

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
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    var selected = country;
    var hasPrefix = false;
    if (raw.startsWith('+') || digits.length > country.phoneDigits) {
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
      if (matches.isNotEmpty) {
        selected = matches.first;
        digits = digits.substring(selected.phoneCode.length - 1);
        hasPrefix = true;
      } else if (!raw.startsWith('+') &&
          country.phoneCode == '+7' &&
          digits.length == 11 &&
          digits.startsWith('8')) {
        digits = digits.substring(1);
        hasPrefix = true;
      } else if (raw.startsWith('+')) {
        return _value('+$digits');
      }
    }
    if (selected.code != country.code) onCountryChanged(selected);
    final maskDigits = selected.phoneGroupSizes.fold<int>(0, (a, b) => a + b);
    if (digits.length > selected.phoneDigits || digits.length > maskDigits) {
      return _value(digits);
    }
    return PhoneInputFormatter(selected).formatEditUpdate(
      hasPrefix ? TextEditingValue.empty : oldValue,
      hasPrefix ? _value(digits) : newValue,
    );
  }

  TextEditingValue _value(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}
