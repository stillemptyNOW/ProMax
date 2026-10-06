import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/digital_id.dart';
import 'package:promax/models/digital_id.dart';

void main() {
  test('profile survives numeric fields from the server', () {
    final docs = DigitalIdUserDocs.fromMap({
      'user_id': 7,
      'digital_profile': {
        'first_name': 'Тест',
        'last_name': 'Тестов',
        'snils': 12345678900,
        'inn': 770000000000,
        'registration_address': {
          'address': 'г. Пример, ул. Образцовая',
          'house': 12,
          'flat': 3,
          'zip_code': 101000,
        },
        'documents': [
          {'type': 'passport', 'series': 4500, 'number': 123456},
          'broken',
        ],
      },
    });
    final profile = docs.profile;
    expect(profile.fullName, 'Тестов Тест');
    expect(profile.snils, '12345678900');
    expect(profile.inn, '770000000000');
    expect(
      profile.registrationAddress!.formatted,
      '101000, г. Пример, ул. Образцовая, д. 12, кв. 3',
    );
    expect(profile.documents.single.series, '4500');
    expect(profile.documents.single.number, '123456');
  });

  test('blank strings read as missing', () {
    final profile = DigitalIdProfile.fromMap({
      'first_name': '  ',
      'gender': '',
    });
    expect(profile.firstName, isNull);
    expect(profile.gender, isNull);
  });

  test('only client-side rejections reset the biometry token', () {
    expect(
      const DigitalIdException('TOKEN', 'x', statusCode: 404).rejectsToken,
      isTrue,
    );
    expect(
      const DigitalIdException(
        'NO_GOSUSLUGI_LINK',
        'x',
        statusCode: 403,
      ).rejectsToken,
      isFalse,
    );
    expect(
      const DigitalIdException('UNAUTHORIZED', 'x', statusCode: 401)
          .rejectsToken,
      isFalse,
    );
    expect(
      const DigitalIdException('HTTP_502', 'x', statusCode: 502).rejectsToken,
      isFalse,
    );
  });
}
