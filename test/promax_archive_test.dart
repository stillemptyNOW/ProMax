import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/config/call_lighting.dart';
import 'package:komet/core/config/promax_archive.dart';
import 'package:komet/core/storage/app_database.dart';
import 'package:komet/core/storage/token_storage.dart';
import 'package:komet_crypto/komet_crypto.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Map<String, dynamic> _message(int account, String id, String text) => {
  'account_id': account,
  'id': id,
  'chat_id': 303,
  'sender_id': 404,
  'time': 10,
  'text': text,
  'deleted': 1,
};
Map<String, dynamic> _chat(int account) => {
  'account_id': account,
  'id': 303,
  'type': 'DIALOG',
  'cached_at': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  KometCrypto.libraryPath = Platform.environment['KOMET_CRYPTO_TEST_LIB'];
  final available = KometCrypto.isAvailable;
  const recoveryKey =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  setUpAll(AppDatabase.init);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'synthetic_promax_archive',
    );
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() async {
      await AppDatabase.close();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    });
    await AppDatabase.saveProfile(ProfileData.stub(101));
    await AppDatabase.saveProfile(ProfileData.stub(202));
    await TokenStorage.setActiveAccount(101);
  });

  test('settings include defaults and never export credentials', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token_101', 'synthetic-secret');
    await prefs.setString('promax_push_relay_secret', 'synthetic-secret');
    final settings = await ProMaxArchive.settings();
    expect(settings['komet_self_online_check'], true);
    expect(settings['komet_anti_read'], false);
    expect(settings['promax_quick_reaction'], '❤️');
    expect(settings.values, isNot(contains('synthetic-secret')));
  });

  test('invalid settings are rejected before any preference changes', () async {
    final data = {
      'format': 'ProMax',
      'version': 1,
      'settings': {'komet_anti_read': true, 'call_light_brightness': 5},
    };
    await expectLater(ProMaxArchive.apply(data), throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('komet_anti_read'), isNull);
  });

  test(
    'a friend imports settings while retaining only their own history',
    () async {
      await AppDatabase.restoreDeletedMessageArchive(
        101,
        [_message(101, 'same-id', 'Synthetic owner')],
        [_chat(101)],
      );
      await AppDatabase.restoreDeletedMessageArchive(
        202,
        [_message(202, 'same-id', 'Synthetic friend')],
        [_chat(202)],
      );
      await TokenStorage.setActiveAccount(202);
      final data = ProMaxArchive.decode(
        utf8.encode(
          jsonEncode({
            'format': 'ProMax',
            'version': 1,
            'settings': {'komet_anti_read': true},
            'deleted': {
              'accountId': 101,
              'ciphertext': 'unreadable synthetic blob',
            },
          }),
        ),
      );
      expect(await ProMaxArchive.prepareDeleted(data), isNull);
      expect(await ProMaxArchive.apply(data), 0);
      expect(
        (await AppDatabase.deletedMessageArchive(202)).messages.single['text'],
        'Synthetic friend',
      );
      expect(
        (await SharedPreferences.getInstance()).getBool('komet_anti_read'),
        true,
      );
    },
  );

  test(
    'restoration preserves existing messages and rolls back mixed accounts',
    () async {
      await AppDatabase.restoreDeletedMessageArchive(
        101,
        [_message(101, 'existing', 'Synthetic existing')],
        [_chat(101)],
      );
      expect(
        await AppDatabase.restoreDeletedMessageArchive(
          101,
          [_message(101, 'existing', 'Synthetic replacement')],
          [_chat(101)],
        ),
        0,
      );
      await expectLater(
        AppDatabase.restoreDeletedMessageArchive(101, [
          _message(101, 'new', 'Synthetic new'),
          _message(202, 'foreign', 'Synthetic foreign'),
        ], []),
        throwsFormatException,
      );
      final rows = (await AppDatabase.deletedMessageArchive(101)).messages;
      expect(rows.length, 1);
      expect(rows.single['text'], 'Synthetic existing');
    },
  );

  test(
    'lighting starts white at 75 percent and restores customization',
    () async {
      final defaults = await CallLighting.load();
      expect(defaults.color, Colors.white);
      expect(defaults.brightness, 0.75);
      await const CallLighting(
        color: Colors.amber,
        brightness: 0.9,
        width: 50,
        opacity: 0.4,
        radius: 10,
      ).save();
      final saved = await CallLighting.load();
      expect(saved.color.toARGB32(), Colors.amber.toARGB32());
      expect(saved.brightness, 0.9);
      expect(saved.width, 50);
      expect(saved.opacity, 0.4);
      expect(saved.radius, 10);
    },
  );

  test(
    'encrypted history rejects account substitution, wrong keys and tampering',
    () {
      final archive = {
        'accountId': 101,
        'messages': [
          _message(101, 'synthetic', 'Synthetic confidential content'),
        ],
        'chats': [_chat(101)],
      };
      final encrypted = ProMaxArchive.seal(101, recoveryKey, archive);
      expect(
        utf8.decode(encrypted, allowMalformed: true),
        isNot(contains('Synthetic confidential')),
      );
      expect(ProMaxArchive.open(101, recoveryKey, encrypted)['accountId'], 101);
      expect(
        () => ProMaxArchive.open(202, recoveryKey, encrypted),
        throwsA(anything),
      );
      expect(
        () => ProMaxArchive.open(101, 'a' * 64, encrypted),
        throwsA(anything),
      );
      final modified = Uint8List.fromList(encrypted)
        ..[encrypted.length - 1] ^= 1;
      expect(
        () => ProMaxArchive.open(101, recoveryKey, modified),
        throwsA(anything),
      );
    },
    skip: !available,
  );

  test(
    'export and import work across the background encryption isolate',
    () async {
      await AppDatabase.restoreDeletedMessageArchive(
        101,
        [_message(101, 'synthetic', 'Synthetic archived content')],
        [_chat(101)],
      );
      await TokenStorage.writeSecure('promax_backup_key_101', recoveryKey);
      final bytes = await ProMaxArchive.export();
      expect(utf8.decode(bytes), isNot(contains('Synthetic archived content')));
      expect(utf8.decode(bytes), isNot(contains(recoveryKey)));
      final prepared = await ProMaxArchive.prepareDeleted(
        ProMaxArchive.decode(bytes),
      );
      expect(
        (prepared!['messages'] as List).single['text'],
        'Synthetic archived content',
      );
    },
    skip: !available,
  );
}
