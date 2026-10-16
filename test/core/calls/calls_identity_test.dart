import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/calls_identity.dart';

void main() {
  test('без подмены и с защитой реальная модель не уходит в звонки', () {
    expect(
      CallsIdentity.device(
        spoofed: false,
        hideRealDevice: true,
        deviceName: 'SynthMaker SynthPhone',
        manufacturer: 'SynthMaker',
        model: 'SynthPhone',
      ),
      isNull,
    );
    expect(
      CallsIdentity.osVersion(
        spoofed: false,
        hideRealDevice: true,
        osVersion: 'Android 13',
        sdkInt: 33,
      ),
      '33',
    );
  });

  test('без защиты сохраняется прежнее поведение', () {
    expect(
      CallsIdentity.device(
        spoofed: false,
        hideRealDevice: false,
        deviceName: 'SynthMaker SynthPhone',
        manufacturer: 'SynthMaker',
        model: 'SynthPhone',
      ),
      'SynthMaker/SynthPhone',
    );
    expect(
      CallsIdentity.osVersion(
        spoofed: false,
        hideRealDevice: false,
        osVersion: 'Android 13',
        sdkInt: 32,
      ),
      '32',
    );
  });

  test('подменённое устройство берётся из профиля', () {
    expect(
      CallsIdentity.device(
        spoofed: true,
        hideRealDevice: true,
        deviceName: 'Samsung Galaxy A54',
        spoofUserAgent:
            'Mozilla/5.0 (Linux; Android 14; SM-A546B) AppleWebKit/537.36',
        manufacturer: 'SynthMaker',
        model: 'SynthPhone',
      ),
      'Samsung/SM-A546B',
    );
    expect(
      CallsIdentity.osVersion(
        spoofed: true,
        hideRealDevice: true,
        osVersion: 'Android 14',
        sdkInt: 30,
      ),
      '34',
    );
  });
}
