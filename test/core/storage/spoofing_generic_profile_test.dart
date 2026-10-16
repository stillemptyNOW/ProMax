import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/device_identity.dart';
import 'package:promax/core/storage/spoofing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('все типовые устройства есть среди пресетов Android', () {
    final presets = SpoofingService.genericPresets;
    expect(
      presets.map((p) => p.deviceName).toSet(),
      SpoofingService.genericDeviceNames.toSet(),
    );
    expect(presets.every((p) => p.deviceType == 'ANDROID'), isTrue);
  });

  test('типовой профиль не несёт реальных часового пояса и языка', () {
    final profile = SpoofingService.buildGenericProfile(
      usedDeviceNames: const {},
      random: Random(7),
      deviceId: '0a1b2c3d',
      instanceId: '00000000-0000-4000-8000-000000000001',
    );
    expect(profile.enabled, isTrue);
    expect(SpoofingService.genericDeviceNames, contains(profile.deviceName));
    expect(profile.timezone, SpoofingService.genericTimezone);
    expect(profile.locale, SpoofingService.genericLanguage);
    expect(profile.deviceLocale, SpoofingService.genericLanguage);
    expect(profile.deviceType, SpoofingService.androidDeviceType);
    expect(profile.appVersion, SpoofingService.hardcodedAppVersion);
    expect(profile.buildNumber, SpoofingService.hardcodedBuildNumber);
    expect(profile.arch, SpoofingService.defaultArchitecture);
    expect(profile.deviceId, '0a1b2c3d');
    expect(profile.instanceId, '00000000-0000-4000-8000-000000000001');
    expect(profile.userAgent, isNotEmpty);
  });

  test('второй аккаунт получает другое типовое устройство', () {
    final used = SpoofingService.genericDeviceNames.skip(1).toSet();
    final profile = SpoofingService.buildGenericProfile(
      usedDeviceNames: used,
      random: Random(1),
      deviceId: 'ffffffff',
      instanceId: 'id',
    );
    expect(profile.deviceName, SpoofingService.genericDeviceNames.first);
  });

  test(
    'профиль для входа создаётся один раз со своими идентификаторами',
    () async {
      await SpoofingService.ensurePendingProfile(
        existingAccountIds: () async => const [],
      );
      final first = await SpoofingService.loadProfile(
        SpoofingService.pendingScope,
      );
      expect(first, isNotNull);
      expect(first!.deviceId, hasLength(16));
      expect(first.deviceId, isNot(await DeviceIdentity.deviceId()));
      expect(first.instanceId, isNot(await DeviceIdentity.instanceId()));

      await SpoofingService.ensurePendingProfile(
        existingAccountIds: () async => const [],
      );
      final second = await SpoofingService.loadProfile(
        SpoofingService.pendingScope,
      );
      expect(second!.deviceId, first.deviceId);
      expect(second.instanceId, first.instanceId);
    },
  );

  test('после входа профиль переезжает на аккаунт', () async {
    await SpoofingService.ensurePendingProfile(
      existingAccountIds: () async => const [],
    );
    final pending = await SpoofingService.loadProfile(
      SpoofingService.pendingScope,
    );
    await SpoofingService.commitPendingSpoof(42);
    final committed = await SpoofingService.loadProfile('42');
    expect(committed!.deviceId, pending!.deviceId);
    expect(
      await SpoofingService.loadProfile(SpoofingService.pendingScope),
      isNull,
    );
    expect(await SpoofingService.sendsRealDevice('42'), isFalse);
  });

  test(
    'скрытие для вошедшего аккаунта сохраняет идентификаторы сессии',
    () async {
      expect(await SpoofingService.sendsRealDevice('7'), isTrue);
      final deviceId = await DeviceIdentity.deviceId();
      final instanceId = await DeviceIdentity.instanceId();

      final profile = await SpoofingService.hideRealDevice('7');

      expect(profile.deviceId, deviceId);
      expect(profile.instanceId, instanceId);
      expect(await SpoofingService.sendsRealDevice('7'), isFalse);
      final session = await SpoofingService.getSpoofedSessionData(scope: '7');
      expect(session!['device_id'], deviceId);
      expect(session['instance_id'], instanceId);
      expect(session['timezone'], SpoofingService.genericTimezone);
    },
  );

  test('ожидающий вход не считается аккаунтом с реальными данными', () async {
    expect(
      await SpoofingService.sendsRealDevice(SpoofingService.pendingScope),
      isFalse,
    );
  });
}
