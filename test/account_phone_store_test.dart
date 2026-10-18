import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/account_phone_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembers the login phone per account', () async {
    await AccountPhoneStore.remember(101, 79990001122);
    await AccountPhoneStore.remember(202, 79990003344);
    expect(await AccountPhoneStore.phoneOf(101), 79990001122);
    expect(await AccountPhoneStore.phoneOf(202), 79990003344);
    expect(await AccountPhoneStore.phoneOf(303), isNull);
  });

  test('ignores empty phones and forgets removed accounts', () async {
    await AccountPhoneStore.remember(101, 0);
    expect(await AccountPhoneStore.phoneOf(101), isNull);
    await AccountPhoneStore.remember(101, 79990001122);
    await AccountPhoneStore.forget(101);
    expect(await AccountPhoneStore.phoneOf(101), isNull);
  });
}
