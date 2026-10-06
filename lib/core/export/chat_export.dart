import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class ExportedMessage {
  const ExportedMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.mine,
  });

  final String id;
  final int senderId;
  final String senderName;
  final String text;
  final int time;
  final bool mine;

  Map<String, Object> toJson() => {
    'id': id,
    's': senderId,
    'n': senderName,
    't': text,
    'tm': time,
    'me': mine,
  };

  static ExportedMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sender = raw['s'];
    final time = raw['tm'];
    if (id is! String || sender is! int || time is! int) return null;
    return ExportedMessage(
      id: id,
      senderId: sender,
      senderName: raw['n'] is String ? raw['n'] as String : '',
      text: raw['t'] is String ? raw['t'] as String : '',
      time: time,
      mine: raw['me'] == true,
    );
  }
}

class ChatExport {
  const ChatExport({
    required this.chatId,
    required this.chatName,
    required this.exportedAt,
    required this.messages,
  });

  final int chatId;
  final String chatName;
  final int exportedAt;
  final List<ExportedMessage> messages;

  static const String format = 'ProMaxChat';
  static const int version = 1;
  static const int memoryKib = 19456;
  static const int iterations = 2;

  Map<String, Object> toJson() => {
    'chat': chatId,
    'name': chatName,
    'at': exportedAt,
    'messages': [for (final m in messages) m.toJson()],
  };

  static ChatExport fromJson(Map<String, dynamic> json) => ChatExport(
    chatId: json['chat'] as int? ?? 0,
    chatName: json['name'] as String? ?? '',
    exportedAt: json['at'] as int? ?? 0,
    messages: [
      for (final raw in (json['messages'] as List? ?? const []))
        ?ExportedMessage.fromJson(raw),
    ],
  );

  String toText() {
    String two(int v) => v.toString().padLeft(2, '0');
    final lines = <String>[
      'Переписка «$chatName»',
      'Экспорт ProMax, ${DateTime.fromMillisecondsSinceEpoch(exportedAt)}',
      '',
    ];
    for (final m in messages) {
      final t = DateTime.fromMillisecondsSinceEpoch(m.time);
      lines.add(
        '[${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}] ${m.senderName}: ${m.text}',
      );
    }
    return lines.join('\n');
  }

  static Future<Uint8List> encrypt(ChatExport export, String password) =>
      Isolate.run(() => _encrypt(export.toJson(), password));

  static Future<ChatExport> decrypt(Uint8List bytes, String password) async {
    final json = await Isolate.run(() => _decrypt(bytes, password));
    return fromJson(json);
  }

  static Future<SecretKey> _key(String password, List<int> salt) => Argon2id(
    parallelism: 1,
    memory: memoryKib,
    iterations: iterations,
    hashLength: 32,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  static Future<Uint8List> _encrypt(
    Map<String, Object> payload,
    String password,
  ) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _key(password, salt);
    final cipher = Xchacha20.poly1305Aead();
    final nonce = cipher.newNonce();
    final header = {
      'format': format,
      'v': version,
      'kdf': 'argon2id',
      'm': memoryKib,
      't': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
    };
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(jsonEncode(header)),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          ...header,
          'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
        }),
      ),
    );
  }

  static Future<Map<String, dynamic>> _decrypt(
    Uint8List bytes,
    String password,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Это не файл экспорта ProMax');
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const FormatException('Это не файл экспорта ProMax');
    }
    if (decoded['v'] != version) {
      throw const FormatException('Неподдерживаемая версия экспорта');
    }
    final salt = base64Decode(decoded['salt'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final data = base64Decode(decoded['data'] as String);
    if (data.length < 16) throw const FormatException('Файл повреждён');
    final header = {
      'format': decoded['format'],
      'v': decoded['v'],
      'kdf': decoded['kdf'],
      'm': decoded['m'],
      't': decoded['t'],
      'salt': decoded['salt'],
      'nonce': decoded['nonce'],
    };
    final key = await _key(password, salt);
    try {
      final clear = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          data.sublist(0, data.length - 16),
          nonce: nonce,
          mac: Mac(data.sublist(data.length - 16)),
        ),
        secretKey: key,
        aad: utf8.encode(jsonEncode(header)),
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const FormatException('Неверный пароль');
    }
  }
}
