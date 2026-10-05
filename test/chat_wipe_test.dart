import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_wipe.dart';
import 'package:promax/backend/modules/messages.dart';

CachedMessage _message(int index, int sender) => CachedMessage(
  id: '${1000 + index}',
  accountId: 1,
  chatId: 77,
  senderId: sender,
  text: 'синтетика $index',
  time: 10000 + index * 10,
);

void main() {
  const me = 1;
  const peer = 2;

  test('walks every page and deletes everything for both', () async {
    final history = [
      for (var i = 0; i < 250; i++) _message(i, i.isEven ? me : peer),
    ];
    final deleted = <String>{};
    var cleared = false;
    var removed = false;
    final result = await ChatWipe.run(
      myId: me,
      fetchPage: (from, count) async {
        final older =
            history.where((m) => from == null || m.time <= from).toList()
              ..sort((a, b) => a.time.compareTo(b.time));
        return older.length <= count
            ? older
            : older.sublist(older.length - count);
      },
      deleteBatch: (ids, {required forEveryone}) async {
        expect(forEveryone, isTrue);
        deleted.addAll(ids);
        return true;
      },
      clearForAll: () async {
        cleared = true;
        return null;
      },
      deleteChatForAll: () async {
        removed = true;
        return null;
      },
    );
    expect(result.found, 250);
    expect(result.deletedForBoth, 250);
    expect(result.complete, isTrue);
    expect(deleted.length, 250);
    expect(cleared && removed, isTrue);
  });

  test(
    'falls back to own messages when the server refuses the peer ones',
    () async {
      final history = [
        for (var i = 0; i < 6; i++) _message(i, i < 4 ? me : peer),
      ];
      final result = await ChatWipe.run(
        myId: me,
        fetchPage: (from, count) async => from == null ? history : const [],
        deleteBatch: (ids, {required forEveryone}) async =>
            ids.every((id) => int.parse(id) < 1004),
        clearForAll: () async => null,
        deleteChatForAll: () async => null,
      );
      expect(result.found, 6);
      expect(result.deletedForBoth, 4);
      expect(result.keptOnPeerSide, 2);
      expect(result.complete, isFalse);
    },
  );

  test('reports a chat deletion error', () async {
    final result = await ChatWipe.run(
      myId: me,
      fetchPage: (from, count) async => const [],
      deleteBatch: (ids, {required forEveryone}) async => true,
      clearForAll: () async => null,
      deleteChatForAll: () async => 'нет доступа',
    );
    expect(result.found, 0);
    expect(result.chatError, 'нет доступа');
  });
}
