import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_wipe.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/backend/modules/server_outcome.dart';
import 'package:promax/core/protocol/packet.dart';

const _me = 1;
const _peer = 2;

CachedMessage _message(int index, int sender) => CachedMessage(
  id: '${1000 + index}',
  accountId: _me,
  chatId: 77,
  senderId: sender,
  text: 'синтетика $index',
  time: 10000 + index * 10,
);

WipeHistoryPage _pagesOf(
  List<CachedMessage> history, {
  int serverLimit = 1000,
}) {
  return (from, count) async {
    final older = history.where((m) => from == null || m.time <= from).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final size = count < serverLimit ? count : serverLimit;
    return older.length <= size ? older : older.sublist(older.length - size);
  };
}

bool _mine(CachedMessage message) => message.senderId == _me;

Future<MessageDeletionReply> _confirmAll(List<String> ids) async =>
    MessageDeletionReply(const ServerDone(), confirmed: ids.toSet());

Future<ServerOutcome> _done(int seen) async => const ServerDone();

void main() {
  test('walks every page and deletes only eligible messages', () async {
    final history = [
      for (var i = 0; i < 250; i++) _message(i, i.isEven ? _me : _peer),
    ];
    final deleted = <String>{};
    var seenByRemoval = 0;
    final result = await ChatWipe.run(
      fetchPage: _pagesOf(history, serverLimit: 40),
      deletableForEveryone: _mine,
      deleteForEveryone: (ids) {
        deleted.addAll(ids);
        return _confirmAll(ids);
      },
      removeChat: (seen) async {
        seenByRemoval = seen;
        return const ServerDone();
      },
      removeForAll: true,
    );

    expect(result.found, 250);
    expect(result.eligible, 125);
    expect(result.deletedForPeer, 125);
    expect(result.keptForPeer, 125);
    expect(result.notConfirmed, 0);
    expect(result.complete, isTrue);
    expect(deleted, {
      for (final m in history)
        if (m.senderId == _me) m.id,
    });
    expect(seenByRemoval, history.last.time);
  });

  test(
    'messages the server leaves out of messageIds are not counted',
    () async {
      final history = [for (var i = 0; i < 6; i++) _message(i, _me)];
      final result = await ChatWipe.run(
        fetchPage: _pagesOf(history),
        deletableForEveryone: _mine,
        deleteForEveryone: (ids) async => MessageDeletionReply(
          const ServerDone(),
          confirmed: ids.take(4).toSet(),
        ),
        removeChat: _done,
        removeForAll: false,
      );

      expect(result.deletedForPeer, 4);
      expect(result.notConfirmed, 2);
      expect(result.complete, isFalse);
      expect(result.deletedIds, hasLength(4));
    },
  );

  test('an OK without messageIds confirms nothing', () async {
    final history = [for (var i = 0; i < 3; i++) _message(i, _me)];
    final result = await ChatWipe.run(
      fetchPage: _pagesOf(history),
      deletableForEveryone: _mine,
      deleteForEveryone: (ids) async =>
          MessageDeletionReply.fromPacket(Packet(cmd: CmdType.ok, payload: {})),
      removeChat: _done,
      removeForAll: false,
    );

    expect(result.deletedForPeer, 0);
    expect(result.notConfirmed, 3);
  });

  test('a batch above the server limit is split instead of dropped', () async {
    final history = [for (var i = 0; i < 230; i++) _message(i, _me)];
    final sizes = <int>[];
    final result = await ChatWipe.run(
      fetchPage: _pagesOf(history),
      deletableForEveryone: _mine,
      deleteForEveryone: (ids) {
        sizes.add(ids.length);
        if (ids.length > 30) {
          throw const PacketError('Слишком много сообщений');
        }
        return _confirmAll(ids);
      },
      removeChat: _done,
      removeForAll: true,
    );

    expect(result.deletedForPeer, 230);
    expect(result.complete, isTrue);
    expect(sizes.last, lessThanOrEqualTo(30));
    expect(sizes.where((size) => size > 30).length, lessThan(4));
  });

  test('a dropped connection stops the wipe and keeps the chat', () async {
    final history = [for (var i = 0; i < 6; i++) _message(i, _me)];
    var removed = false;
    final result = await ChatWipe.run(
      fetchPage: _pagesOf(history),
      deletableForEveryone: _mine,
      deleteForEveryone: (ids) async => throw StateError('Нет соединения'),
      removeChat: (seen) async {
        removed = true;
        return const ServerDone();
      },
      removeForAll: true,
    );

    expect(result.unreachable, isTrue);
    expect(result.chatRemoved, isFalse);
    expect(result.deletedForPeer, 0);
    expect(removed, isFalse);
  });

  test('a history error keeps what was found and reports it', () async {
    final history = [for (var i = 0; i < 150; i++) _message(i, _me)];
    final pages = _pagesOf(history);
    var page = 0;
    final result = await ChatWipe.run(
      fetchPage: (from, count) async {
        if (page++ > 0) throw const PacketError('История недоступна');
        return pages(from, count);
      },
      deletableForEveryone: _mine,
      deleteForEveryone: _confirmAll,
      removeChat: _done,
      removeForAll: true,
    );

    expect(result.found, 100);
    expect(result.historyIncomplete, isTrue);
    expect(result.deletedForPeer, 100);
    expect(result.complete, isFalse);
  });

  test('a refused chat removal is reported with its reason', () async {
    final result = await ChatWipe.run(
      fetchPage: (from, count) async => const [],
      deletableForEveryone: _mine,
      deleteForEveryone: _confirmAll,
      removeChat: (seen) async => const ServerRejected('нет доступа'),
      removeForAll: false,
    );

    expect(result.found, 0);
    expect(result.chatError, 'нет доступа');
    expect(result.chatRemoved, isFalse);
  });

  test('server error responses map to typed outcomes', () async {
    final notFound = await runServerAction(
      () async => Packet(cmd: CmdType.notFound, payload: {'message': 'нет'}),
    );
    expect(notFound, isA<ServerRejected>());
    expect((notFound as ServerRejected).notFound, isTrue);

    final refused = await runServerAction(
      () async => throw const PacketError('отказ', errorKey: 'error.denied'),
    );
    expect(refused, isA<ServerRejected>());

    final busy = await runServerAction(
      () async => throw const PacketError('позже', errorKey: 'not.ready'),
    );
    expect(busy, isA<ServerUnreachable>());

    final expired = await runServerAction(
      () async => throw const SessionExpiredException('сессия'),
    );
    expect(expired, isA<ServerUnreachable>());

    final ok = await runServerAction(() async => Packet(cmd: CmdType.ok));
    expect(ok, isA<ServerDone>());
  });

  test('confirmed ids are read from the MSG_DELETE answer', () {
    final reply = MessageDeletionReply.fromPacket(
      Packet(
        cmd: CmdType.ok,
        payload: {
          'chatId': 77,
          'messageIds': [1001, 1003],
        },
      ),
    );

    expect(reply.confirmed, {'1001', '1003'});
    expect(reply.unconfirmedOf(['1001', '1002', '1003', 'temp_1']), ['1002']);
  });
}
