import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/security/app_lock.dart';
import 'package:promax/core/security/double_bottom.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await DoubleBottom.clear();
  });

  test('the second code opens the decoy and the main code closes it', () async {
    final lock = AppLock.instance;
    await lock.setPin('1111');
    expect(await lock.setDecoyPin('1111'), isFalse);
    expect(await lock.setDecoyPin('2222'), isTrue);
    expect(lock.decoyConfigured.value, isTrue);

    await DoubleBottom.setSecret(501, true);
    expect(DoubleBottom.hides(501), isFalse);

    lock.lock();
    expect(await lock.unlockWithPin('2222'), isTrue);
    expect(DoubleBottom.active.value, isTrue);
    expect(DoubleBottom.hides(501), isTrue);
    expect(DoubleBottom.hides(502), isFalse);

    lock.lock();
    expect(await lock.unlockWithPin('1111'), isTrue);
    expect(DoubleBottom.active.value, isFalse);
    expect(DoubleBottom.hides(501), isFalse);
  });

  test('turning the lock off removes the decoy', () async {
    final lock = AppLock.instance;
    await lock.setPin('1234');
    await lock.setDecoyPin('4321');
    await DoubleBottom.setActive(true);
    await lock.disable();
    expect(lock.decoyConfigured.value, isFalse);
    expect(DoubleBottom.active.value, isFalse);
  });

  test('secret chats persist across loads', () async {
    await DoubleBottom.setSecret(-7, true);
    await DoubleBottom.setSecret(8, true);
    await DoubleBottom.setSecret(8, false);
    DoubleBottom.secretChats.value = const {};
    await DoubleBottom.load();
    expect(DoubleBottom.secretChats.value, {-7});
  });
}
