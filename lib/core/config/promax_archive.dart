import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:promax_crypto/promax_crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/e2ee_service.dart';
import '../storage/app_database.dart';
import '../storage/token_storage.dart';
import 'promax_settings.dart';
import 'call_lighting.dart';

class ProMaxArchive {
  static const maxBytes = 64 * 1024 * 1024;
  static const boolKeys = {
    'promax_view_deleted',
    'promax_view_redacted',
    'promax_full_timestamp',
    'promax_show_forward',
    'promax_show_typing_time',
    'promax_ghost_mode',
    'promax_anti_read',
    'promax_self_online_check',
    'promax_hide_all_chats_folder',
    'promax_show_hidden_chats',
    'promax_archive_on_pull',
    'promax_record_debug_logs',
    'app_amoled',
    'dev_video_note_rear_camera',
    'call_light_wide_default',
    'promax_no_typing',
    'promax_hide_story_views',
    'promax_atmosphere_triggers',
  };
  static const stringValues = {
    'app_theme_mode': {'system', 'light', 'dark', 'schedule'},
    'app_font': {'system', 'inter', 'unbounded'},
    'promax_atmosphere_effect': {
      'none',
      'snow',
      'rain',
      'stars',
      'leaves',
      'sakura',
      'hearts',
      'confetti',
      'sparkles',
      'bubbles',
      'fireflies',
    },
    'promax_atmosphere_scope': {'everywhere', 'chats'},
    'promax_theme_preset': {
      'graphite',
      'aurora',
      'sunset',
      'ocean',
      'forest',
      'neon',
      'sakura',
      'winter',
      'night',
      'system',
    },
  };
  static const numbers = {
    'app_accent_seed': (min: 0.0, max: 4294967295.0, integer: true),
    'app_font_scale': (min: 0.6, max: 1.35, integer: false),
    'call_light_color': (min: 0.0, max: 4294967295.0, integer: true),
    'call_light_brightness': (min: 0.1, max: 1.0, integer: false),
    'call_light_width': (min: 4.0, max: 100.0, integer: false),
    'call_light_opacity': (min: 0.1, max: 1.0, integer: false),
    'call_light_radius': (min: 0.0, max: 100.0, integer: false),
    'promax_glass_blur': (min: 0.0, max: 2.5, integer: false),
    'promax_glass_refraction': (min: 0.0, max: 40.0, integer: false),
    'promax_glass_specular': (min: 0.0, max: 1.0, integer: false),
    'promax_glass_chroma': (min: 0.0, max: 0.4, integer: false),
    'promax_glass_rim': (min: 0.0, max: 5.0, integer: false),
    'promax_glass_tint': (min: 0.0, max: 2.5, integer: false),
    'promax_atmosphere_density': (min: 0.2, max: 3.0, integer: false),
    'promax_atmosphere_speed': (min: 0.2, max: 3.0, integer: false),
    'promax_atmosphere_size': (min: 0.4, max: 2.5, integer: false),
    'promax_atmosphere_opacity': (min: 0.1, max: 1.0, integer: false),
    'promax_atmosphere_wind': (min: -1.0, max: 1.0, integer: false),
    'promax_atmosphere_color': (min: 0.0, max: 4294967295.0, integer: true),
  };

  static bool validSetting(String key, Object? value) {
    if (boolKeys.contains(key)) return value is bool;
    if (key == 'promax_quick_reaction') {
      return value is String && value.isNotEmpty && value.length <= 32;
    }
    if (stringValues.containsKey(key)) {
      return stringValues[key]!.contains(value);
    }
    if (key == 'dev_video_note_resolution') {
      return value is int && {480, 720, 1080}.contains(value);
    }
    if (key == 'dev_video_note_fps') {
      return value is int && {30, 60}.contains(value);
    }
    final bound = numbers[key];
    if (bound == null || value is! num || !value.isFinite) return false;
    return (!bound.integer || value is int) &&
        value >= bound.min &&
        value <= bound.max;
  }

  static Future<Map<String, Object>> settings() async {
    await CallLighting.load();
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in boolKeys)
        key:
            key == 'promax_self_online_check' ||
            key == 'call_light_wide_default' ||
            key == 'promax_atmosphere_triggers',
      'promax_quick_reaction': '❤️',
      'app_theme_mode': 'system',
      'app_font': 'system',
      'app_font_scale': 1.0,
      'dev_video_note_resolution': 480,
      'dev_video_note_fps': 30,
      'call_light_color': 0xffffffff,
      'call_light_brightness': 0.75,
      'call_light_width': 64.0,
      'call_light_opacity': 1.0,
      'call_light_radius': 36.0,
      for (final key in prefs.getKeys())
        if (validSetting(key, prefs.get(key))) key: prefs.get(key)!,
    };
  }

  static Map<String, dynamic> decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Некорректный размер .promax');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['format'] != 'ProMax' ||
        value['version'] != 1 ||
        value['settings'] is! Map) {
      throw const FormatException('Это не поддерживаемый файл .promax');
    }
    final config = Map<String, dynamic>.from(value['settings'] as Map);
    if (config.entries.any((entry) => !validSetting(entry.key, entry.value))) {
      throw const FormatException(
        'В файле есть неизвестные или некорректные настройки',
      );
    }
    if (value['deleted'] != null) {
      final backup = value['deleted'];
      if (backup is! Map ||
          backup['accountId'] is! int ||
          backup['ciphertext'] is! String) {
        throw const FormatException('Некорректный архив сообщений');
      }
    }
    return Map<String, dynamic>.from(value);
  }

  static Uint8List _key(String recoveryKey) {
    final value = recoveryKey.replaceAll(RegExp(r'\s'), '').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException(
        'Ключ должен содержать 64 шестнадцатеричных символа',
      );
    }
    return Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ]);
  }

  static Future<String> recoveryKey(int accountId) async {
    final name = 'promax_backup_key_$accountId';
    final existing = await TokenStorage.readSecure(name);
    if (existing != null) {
      _key(existing);
      return existing;
    }
    final random = Random.secure();
    final value = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await TokenStorage.writeSecure(name, value);
    return value;
  }

  static Uint8List seal(
    int accountId,
    String recoveryKey,
    Map<String, dynamic> archive,
  ) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(archive)));
    if (bytes.length > maxBytes * 0.7) {
      throw const FormatException('Архив сообщений превышает лимит 44 МБ');
    }
    return ProMaxCrypto.localSeal(
      key: _key(recoveryKey),
      plaintext: bytes,
      aad: Uint8List.fromList(utf8.encode('ProMax:deleted:1:$accountId')),
    );
  }

  static Map<String, dynamic> open(
    int accountId,
    String recoveryKey,
    Uint8List ciphertext,
  ) {
    final bytes = ProMaxCrypto.localOpen(
      key: _key(recoveryKey),
      blob: ciphertext,
      aad: Uint8List.fromList(utf8.encode('ProMax:deleted:1:$accountId')),
    );
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['accountId'] != accountId ||
        data['messages'] is! List ||
        data['chats'] is! List) {
      throw const FormatException('Архив принадлежит другому аккаунту');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<Uint8List> export() async {
    final accountId = await TokenStorage.getActiveAccountId();
    final data = <String, dynamic>{
      'format': 'ProMax',
      'version': 1,
      'settings': await settings(),
    };
    if (accountId != null) {
      final rows = await AppDatabase.deletedMessageArchive(accountId);
      if (rows.messages.isNotEmpty) {
        final messages = <Map<String, dynamic>>[];
        for (final original in rows.messages) {
          final row = Map<String, dynamic>.from(original);
          final sealed = row.remove('text_sealed');
          if (sealed is Uint8List && row['e2ee'] == 1) {
            final text = await E2eeService.instance.openText(
              accountId,
              row['chat_id'] as int,
              sealed,
            );
            if (text == null) {
              throw const FormatException(
                'Не удалось расшифровать локальную историю',
              );
            }
            row['backupText'] = text;
          }
          messages.add(row);
        }
        final archive = <String, dynamic>{
          'accountId': accountId,
          'messages': messages,
          'chats': rows.chats,
        };
        final key = await recoveryKey(accountId);
        final libraryPath = ProMaxCrypto.libraryPath;
        final encrypted = await Isolate.run(() {
          ProMaxCrypto.libraryPath = libraryPath;
          return seal(accountId, key, archive);
        });
        data['deleted'] = {
          'accountId': accountId,
          'ciphertext': base64Encode(encrypted),
        };
      }
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > maxBytes) {
      throw const FormatException('Файл .promax слишком большой');
    }
    return bytes;
  }

  static Future<Map<String, dynamic>?> prepareDeleted(
    Map<String, dynamic> data, {
    String? suppliedKey,
  }) async {
    final backup = data['deleted'];
    if (backup is! Map) return null;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null || backup['accountId'] != accountId) return null;
    final key =
        suppliedKey ??
        await TokenStorage.readSecure('promax_backup_key_$accountId');
    if (key == null) {
      throw const FormatException('Для истории нужен ключ восстановления');
    }
    final encrypted = base64Decode(backup['ciphertext'] as String);
    final libraryPath = ProMaxCrypto.libraryPath;
    final archive = await Isolate.run(() {
      ProMaxCrypto.libraryPath = libraryPath;
      return open(accountId, key, encrypted);
    });
    final messages = (archive['messages'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final chats = (archive['chats'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (messages.any(
          (row) =>
              row['account_id'] != accountId ||
              row['deleted'] != 1 ||
              row['id'] is! String ||
              row['chat_id'] is! int ||
              row['sender_id'] is! int ||
              row['time'] is! int,
        ) ||
        chats.any(
          (row) => row['account_id'] != accountId || row['id'] is! int,
        )) {
      throw const FormatException('Некорректные данные аккаунта в архиве');
    }
    for (final row in messages) {
      final plaintext = row.remove('backupText');
      if (plaintext is String) {
        row['text_sealed'] = await E2eeService.instance.sealText(
          accountId,
          row['chat_id'] as int,
          plaintext,
        );
      }
    }
    archive['messages'] = messages;
    archive['chats'] = chats;
    archive['recoveryKey'] = key;
    return archive;
  }

  static Future<int> apply(
    Map<String, dynamic> data, {
    Map<String, dynamic>? deleted,
  }) async {
    final validated = decode(utf8.encode(jsonEncode(data)));
    final accountId = await TokenStorage.getActiveAccountId();
    var restored = 0;
    if (deleted != null) {
      if (deleted['accountId'] != accountId) {
        throw const FormatException('Сменился аккаунт. Повторите импорт');
      }
      restored = await AppDatabase.restoreDeletedMessageArchive(
        accountId!,
        (deleted['messages'] as List).cast<Map<String, dynamic>>(),
        (deleted['chats'] as List).cast<Map<String, dynamic>>(),
      );
      await TokenStorage.writeSecure(
        'promax_backup_key_$accountId',
        deleted['recoveryKey'] as String,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    for (final entry in (validated['settings'] as Map).entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int && numbers[key]?.integer == false) {
        await prefs.setDouble(key, value.toDouble());
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    }
    await ProMaxSettings.load();
    return restored;
  }
}
