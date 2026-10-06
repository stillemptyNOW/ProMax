import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/export/chat_export.dart';

void main() {
  final export = ChatExport(
    chatId: 77,
    chatName: 'Синтетический чат',
    exportedAt: DateTime(2026, 10, 6).millisecondsSinceEpoch,
    messages: [
      for (var i = 0; i < 50; i++)
        ExportedMessage(
          id: '$i',
          senderId: i.isEven ? 1 : 2,
          senderName: i.isEven ? 'Я' : 'Собеседник',
          text: 'синтетическое сообщение $i',
          time: DateTime(2026, 10, 6, 12, i).millisecondsSinceEpoch,
          mine: i.isEven,
        ),
    ],
  );

  test('encrypted export round-trips and rejects a wrong password', () async {
    final bytes = await ChatExport.encrypt(export, 'пароль-синтетика');
    expect(utf8.decode(bytes), isNot(contains('синтетическое')));
    final opened = await ChatExport.decrypt(bytes, 'пароль-синтетика');
    expect(opened.chatName, export.chatName);
    expect(opened.messages.length, 50);
    expect(opened.messages[3].text, 'синтетическое сообщение 3');
    await expectLater(
      ChatExport.decrypt(bytes, 'не тот'),
      throwsA(isA<FormatException>()),
    );
  });

  test('tampered and foreign files are rejected', () async {
    final bytes = await ChatExport.encrypt(export, 'x');
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    json['m'] = 1024;
    await expectLater(
      ChatExport.decrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
        'x',
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      ChatExport.decrypt(Uint8List.fromList(utf8.encode('{}')), 'x'),
      throwsA(isA<FormatException>()),
    );
  });

  test('plain text transcript lists every message', () {
    final text = export.toText();
    expect(text, contains('Переписка «Синтетический чат»'));
    expect(text.split('\n').length, 53);
  });
}
