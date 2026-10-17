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

Future<ServerOutcome> _done(int seen) async => const ServerDone();

bool _isPeer(String id) => int.parse(id).isOdd;

void main() {
  test('walks every page even when the server returns short pages', () async {
    final history = [
      for (var i = 0; i < 250; i++) _message(i, i.isEven ? _me : _peer),
    ];
    final deleted = <String>{};
    var seenByClear = 0;
    var seenByDelete = 0;
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: _pagesOf(history, serverLimit: 40),
      deleteBatch: (ids, {required forEveryone}) async {
        expect(forEveryone, isTrue);
        deleted.addAll(ids);
        return const ServerDone();
      },
      clearForAll: (seen) async {
        seenByClear = seen;
        return const ServerDone();
      },
      removeChat: (seen) async {
        seenByDelete = seen;
        return const ServerDone();
      },
    );
    expect(result.found, 250);
    expect(result.ownForBoth, 125);
    expect(result.peerForBoth, 125);
    expect(result.onlyForMe, 0);
    expect(result.complete, isTrue);
    expect(deleted.length, 250);
    expect(seenByClear, history.last.time);
    expect(seenByDelete, history.last.time);
  });

  test(
    'peer messages refused with PacketError are deleted only for me',
    () async {
      final history = [
        for (var i = 0; i < 12; i++) _message(i, i.isOdd ? _peer : _me),
      ];
      final calls = <({List<String> ids, bool forEveryone})>[];
      final result = await ChatWipe.run(
        myId: _me,
        fetchPage: _pagesOf(history),
        deleteBatch: (ids, {required forEveryone}) async {
          calls.add((ids: ids, forEveryone: forEveryone));
          if (forEveryone && ids.any(_isPeer)) {
            throw const PacketError(
              'Нельзя удалить чужое сообщение',
              errorKey: 'error.message.delete',
            );
          }
          return const ServerDone();
        },
        clearForAll: _done,
        removeChat: _done,
      );
      expect(result.found, 12);
      expect(result.ownForBoth, 6);
      expect(result.peerForBoth, 0);
      expect(result.onlyForMe, 6);
      expect(result.notDeleted, 0);
      expect(result.chatRemoved, isTrue);
      expect(result.complete, isFalse);
      final ownCalls = calls.where((c) => !c.ids.any(_isPeer));
      expect(ownCalls.every((c) => c.forEveryone), isTrue);
      expect(calls.where((c) => c.forEveryone && c.ids.any(_isPeer)).length, 1);
      expect(result.deletedIds.toSet(), history.map((m) => m.id).toSet());
    },
  );

  test('peer messages the server accepts count as deleted for both', () async {
    final history = [
      for (var i = 0; i < 6; i++) _message(i, i < 2 ? _me : _peer),
    ];
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: _pagesOf(history),
      deleteBatch: (ids, {required forEveryone}) async => const ServerDone(),
      clearForAll: _done,
      removeChat: _done,
    );
    expect(result.ownForBoth, 2);
    expect(result.peerForBoth, 4);
    expect(result.complete, isTrue);
  });

  test('a batch above the server limit is split instead of dropped', () async {
    final history = [for (var i = 0; i < 230; i++) _message(i, _me)];
    final sizes = <int>[];
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: _pagesOf(history),
      deleteBatch: (ids, {required forEveryone}) async {
        sizes.add(ids.length);
        if (ids.length > 30) {
          throw const PacketError('Слишком много сообщений');
        }
        return const ServerDone();
      },
      clearForAll: _done,
      removeChat: _done,
    );
    expect(result.ownForBoth, 230);
    expect(result.complete, isTrue);
    expect(sizes.last, lessThanOrEqualTo(30));
    expect(sizes.where((size) => size > 30).length, lessThan(4));
  });

  test('a dropped connection stops the wipe and keeps the chat', () async {
    final history = [for (var i = 0; i < 6; i++) _message(i, _me)];
    var finished = false;
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: _pagesOf(history),
      deleteBatch: (ids, {required forEveryone}) async =>
          throw StateError('Нет соединения'),
      clearForAll: (seen) async {
        finished = true;
        return const ServerDone();
      },
      removeChat: (seen) async {
        finished = true;
        return const ServerDone();
      },
    );
    expect(result.unreachable, isTrue);
    expect(result.chatRemoved, isFalse);
    expect(result.notDeleted, 6);
    expect(finished, isFalse);
  });

  test('a history error keeps what was found and reports it', () async {
    final history = [for (var i = 0; i < 150; i++) _message(i, _me)];
    final pages = _pagesOf(history);
    var page = 0;
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: (from, count) async {
        if (page++ > 0) throw const PacketError('История недоступна');
        return pages(from, count);
      },
      deleteBatch: (ids, {required forEveryone}) async => const ServerDone(),
      clearForAll: _done,
      removeChat: _done,
    );
    expect(result.found, 100);
    expect(result.historyIncomplete, isTrue);
    expect(result.ownForBoth, 100);
    expect(result.complete, isFalse);
  });

  test('clear and delete refusals are reported separately', () async {
    final result = await ChatWipe.run(
      myId: _me,
      fetchPage: (from, count) async => const [],
      deleteBatch: (ids, {required forEveryone}) async => const ServerDone(),
      clearForAll: (seen) async =>
          const ServerRejected('чат не найден', notFound: true),
      removeChat: (seen) async => const ServerRejected('нет доступа'),
    );
    expect(result.found, 0);
    expect(result.clearError, 'чат не найден');
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
}
