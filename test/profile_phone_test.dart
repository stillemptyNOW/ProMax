import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/app_database.dart';

void main() {
  test('parses phone numbers sent as numbers or strings', () {
    expect(ProfileData.parsePhone(79990001122), 79990001122);
    expect(ProfileData.parsePhone(79990001122.0), 79990001122);
    expect(ProfileData.parsePhone('+7 (999) 000-11-22'), 79990001122);
    expect(ProfileData.parsePhone('79990001122'), 79990001122);
  });

  test('treats missing or hidden phones as unknown', () {
    expect(ProfileData.parsePhone(null), 0);
    expect(ProfileData.parsePhone(''), 0);
    expect(ProfileData.parsePhone('скрыт'), 0);
    expect(ProfileData.parsePhone('12'), 0);
  });
}
