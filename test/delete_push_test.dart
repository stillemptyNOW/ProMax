import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chat_deletion_plan.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/backend/modules/server_outcome.dart';
import 'package:promax/core/cache/message_session_cache.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:promax/core/utils/server_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String directory;

  _SyntheticPathProvider(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class _PushOnlyApi extends Api {
  final pushes = StreamController<Packet>.broadcast();
  final states = StreamController<SessionState>.broadcast();
  final requests = <(int, Map<dynamic, dynamic>)>[];
  Object? Function(int opcode) reply = (_) => null;
  int epoch = 0;

  @override
  int get sessionEpoch => epoch;

  @override
  Stream<Packet> get pushStream => pushes.stream;

  @override
  Stream<SessionState> get stateStream => states.stream;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    beforeSend?.call();
    requests.add((opcode, payload));
    final answer = reply(opcode);
    if (answer is Packet) return answer;
    return Packet(
      cmd: CmdType.ok,
      opcode: opcode,
      payload: answer ?? <String, Object>{},
    );
  }
}

const int _me = 1;
const int _chatId = 900601;
const int _peer = 900701;

Map<String, Object> _chat() => {
  'id': _chatId,
  'type': 'DIALOG',
  'status': 'ACTIVE',
  'lastEventTime': 6000,
  'participants': {'$_me': 0, '$_peer': 0},
};

CachedMessage _stored(String id, int time, {String? status}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: _chatId,
  senderId: _peer,
  text: 'синтетика $id',
  time: time,
  status: status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _PushOnlyApi();

  setUpAll(() => chats.attachGlobalPushHandlers(api));

  tearDownAll(() async {
    await api.pushes.close();
    await api.states.close();
    await api.dispose();
  });

  setUp(() async {
    api.requests.clear();
    api.reply = (_) => null;
    MessageSessionCache.clearAll();
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync(
      'synthetic_delete_push_test',
    );
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
      ServerClock.resetForTest();
      ProMaxSettings.viewDeleted.value = false;
      await AppDatabase.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(_me));
    await TokenStorage.setActiveAccount(_me);
    await chats.cacheServerChat(_chat(), _me);
    await AppDatabase.saveMessages([
      for (var i = 1; i <= 5; i++) _stored('81$i', i * 1000).toDbRow(),
      _stored('temp_1_1', 3000, status: 'sending').toDbRow(),
    ]);
  });

  Future<List<MessageEvent>> deliver(Packet packet, int expected) async {
    final events = chats.messageEvents
        .where((e) => e.chatId == _chatId)
        .take(expected)
        .toList();
    api.pushes.add(packet);
    final delivered = await events.timeout(const Duration(seconds: 5));
    await chats.pushesHandled;
    return delivered;
  }

  Future<Set<String>> storedIds({bool onlyVisible = false}) async => {
    for (final row in await AppDatabase.loadMessages(
      _me,
      _chatId,
      onlyVisible: onlyVisible,
    ))
      row['id'].toString(),
  };

  Packet range(int start, int end) => Packet(
    cmd: CmdType.push,
    opcode: Opcode.notifMsgDeleteRange,
    payload: {'chat': _chat(), 'startTime': start, 'endTime': end},
  );

  test('a cleared range disappears from the local history', () async {
    final events = await deliver(range(2000, 4000), 3);

    expect(events.whereType<MessageRemovedEvent>().map((e) => e.messageId), {
      '812',
      '813',
      '814',
    });
    expect(await storedIds(), {'811', '815', 'temp_1_1'});
  });

  test('with "show deleted" the range stays but is marked', () async {
    ProMaxSettings.viewDeleted.value = true;
    final events = await deliver(range(0, 2000), 2);

    expect(events, everyElement(isA<MessageMarkedDeletedEvent>()));
    expect(await storedIds(), hasLength(6));
    expect(await storedIds(onlyVisible: true), {
      '813',
      '814',
      '815',
      'temp_1_1',
    });
  });

  test('a single deletion push removes the messages', () async {
    final events = await deliver(
      Packet(
        cmd: CmdType.push,
        opcode: Opcode.notifMsgDelete,
        payload: {
          'chat': _chat(),
          'messageIds': [815, 811],
        },
      ),
      2,
    );

    expect(events, everyElement(isA<MessageRemovedEvent>()));
    expect(await storedIds(), {'812', '813', '814', 'temp_1_1'});
  });

  Packet chatPush(Map<String, Object> chat) => Packet(
    cmd: CmdType.push,
    opcode: Opcode.notifChat,
    payload: {'chat': chat},
  );

  test('a dialog removed on the server leaves with its history', () async {
    final departed = chats.departedChats.first;
    final events = await deliver(
      chatPush({..._chat(), 'status': 'REMOVED'}),
      5,
    );

    expect(events, everyElement(isA<MessageRemovedEvent>()));
    expect(await departed.timeout(const Duration(seconds: 5)), _chatId);
    final rows = await AppDatabase.loadChat(_me, _chatId);
    expect(rows.single['in_list'], 2);
    expect(await storedIds(), {'temp_1_1'});
    expect(
      chats.chatsSnapshot().map((chat) => chat.id),
      isNot(contains(_chatId)),
    );
  });

  test('a short removal push is not ignored', () async {
    await deliver(chatPush({'id': _chatId, 'status': 'REMOVED'}), 5);

    final rows = await AppDatabase.loadChat(_me, _chatId);
    expect(rows.single['in_list'], 2);
    expect(await storedIds(), {'temp_1_1'});
  });

  test('with "show deleted" a removed dialog keeps marked messages', () async {
    ProMaxSettings.viewDeleted.value = true;
    final events = await deliver(
      chatPush({..._chat(), 'status': 'REMOVED'}),
      5,
    );

    expect(events, everyElement(isA<MessageMarkedDeletedEvent>()));
    expect(await storedIds(), hasLength(6));
    expect(await storedIds(onlyVisible: true), {'temp_1_1'});
  });

  test('a group the server marks removed keeps its history', () async {
    api.pushes.add(chatPush({..._chat(), 'type': 'CHAT', 'status': 'REMOVED'}));
    await Future<void>.delayed(Duration.zero);
    await chats.pushesHandled;

    final rows = await AppDatabase.loadChat(_me, _chatId);
    expect(rows.single['in_list'], 2);
    expect(await storedIds(), hasLength(6));
  });

  test('a removed message also leaves the open chat cache', () async {
    MessageSessionCache.save(_me, _chatId, [
      for (var i = 1; i <= 5; i++) _stored('81$i', i * 1000),
    ], reachedStart: true);

    final events = await deliver(
      Packet(
        cmd: CmdType.push,
        opcode: Opcode.notifMessage,
        payload: {
          'chatId': _chatId,
          'message': {
            'id': 815,
            'sender': _peer,
            'time': 5000,
            'status': 'REMOVED',
          },
        },
      ),
      1,
    );

    expect(events.single, isA<MessageRemovedEvent>());
    expect(await storedIds(), isNot(contains('815')));
    expect(
      MessageSessionCache.get(_me, _chatId)!.messages.map((m) => m.id),
      isNot(contains('815')),
    );
  });

  group('deleting a dialog', () {
    Packet refusal(int opcode) => Packet(
      cmd: CmdType.error,
      opcode: opcode,
      payload: {'localizedMessage': 'синтетический отказ'},
    );

    test('a dialog is deleted only for me even if forAll is asked', () async {
      final result = await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: true,
        accountId: _me,
      );

      expect(result.ok, isTrue);
      expect(result.forAll, isFalse);
      expect(api.requests.map((r) => r.$1), [Opcode.chatDelete]);
      expect(api.requests.single.$2, {
        'chatId': _chatId,
        'lastEventTime': 6000,
        'forAll': false,
      });
      expect(await AppDatabase.loadChat(_me, _chatId), isEmpty);
      expect(await storedIds(), isEmpty);
    });

    test('lastEventTime comes from the chat, never from the clock', () async {
      ServerClock.sync(
        DateTime.now().millisecondsSinceEpoch + 5 * 86400 * 1000,
      );

      await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: true,
        accountId: _me,
      );

      expect(api.requests.single.$2['lastEventTime'], 6000);
    });

    test('a newer message the screen saw moves lastEventTime up', () async {
      await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: true,
        seenEventTime: 7000,
        accountId: _me,
      );

      expect(api.requests.single.$2['lastEventTime'], 7000);
    });

    test('keeps the chat and says why when the server refuses', () async {
      api.reply = (opcode) =>
          opcode == Opcode.chatDelete ? refusal(opcode) : null;

      final result = await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: true,
        accountId: _me,
      );

      expect((result.outcome as ServerRejected).message, 'синтетический отказ');
      expect(await AppDatabase.loadChat(_me, _chatId), isNotEmpty);
      expect(await storedIds(), hasLength(6));
    });

    test('another active account gets no request at all', () async {
      await TokenStorage.setActiveAccount(_me + 1);
      addTearDown(() => TokenStorage.setActiveAccount(_me));

      final result = await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: true,
        accountId: _me,
      );

      expect(result.outcome, isA<ServerUnreachable>());
      expect(api.requests, isEmpty);
    });

    const unknownChat = 900602;

    Object? chatInfoReply(int opcode, List<Map<String, Object>> found) =>
        opcode == Opcode.chatInfo ? {'chats': found} : null;

    test(
      'a dialog missing locally takes its type and time from the server',
      () async {
        api.reply = (opcode) => chatInfoReply(opcode, [
          {
            'id': unknownChat,
            'type': 'DIALOG',
            'status': 'ACTIVE',
            'lastEventTime': 8000,
          },
        ]);

        final result = await chats.deleteChat(
          api,
          chatId: unknownChat,
          forAll: true,
          accountId: _me,
        );

        expect(result.ok, isTrue);
        expect(api.requests.map((r) => r.$1), [
          Opcode.chatInfo,
          Opcode.chatDelete,
        ]);
        expect(api.requests.last.$2, {
          'chatId': unknownChat,
          'lastEventTime': 8000,
          'forAll': false,
        });
      },
    );

    test('only the owner deletes a group for its members', () async {
      for (final owner in [_me, _peer]) {
        api.requests.clear();
        api.reply = (opcode) => chatInfoReply(opcode, [
          {
            'id': unknownChat,
            'type': 'CHAT',
            'owner': owner,
            'lastEventTime': 8000,
          },
        ]);

        await chats.deleteChat(
          api,
          chatId: unknownChat,
          forAll: true,
          accountId: _me,
        );

        expect(api.requests.last.$1, Opcode.chatDelete);
        expect(api.requests.last.$2['forAll'], owner == _me);
      }
    });

    test('a channel goes out without forAll even for its owner', () async {
      api.reply = (opcode) => chatInfoReply(opcode, [
        {
          'id': unknownChat,
          'type': 'CHANNEL',
          'owner': _me,
          'lastEventTime': 8000,
        },
      ]);

      await chats.deleteChat(
        api,
        chatId: unknownChat,
        forAll: true,
        accountId: _me,
      );

      expect(api.requests.last.$1, Opcode.chatDelete);
      expect(api.requests.last.$2['forAll'], isFalse);
    });

    test('a chat of unknown type is never deleted for everyone', () async {
      api.reply = (opcode) => chatInfoReply(opcode, []);

      final result = await chats.deleteChat(
        api,
        chatId: unknownChat,
        forAll: true,
        accountId: _me,
      );

      expect(result.refusal, ChatDeletionRefusal.typeUnknown);
      expect(result.ok, isFalse);
      expect(api.requests.map((r) => r.$1), [Opcode.chatInfo]);
    });

    test('without any known event time nothing is sent', () async {
      api.reply = (opcode) => chatInfoReply(opcode, [
        {'id': unknownChat, 'type': 'DIALOG', 'status': 'ACTIVE'},
      ]);

      final result = await chats.deleteChat(
        api,
        chatId: unknownChat,
        forAll: false,
        accountId: _me,
      );

      expect(result.refusal, ChatDeletionRefusal.eventTimeUnknown);
      expect(api.requests.map((r) => r.$1), isNot(contains(Opcode.chatDelete)));
    });

    test('only for me sends a single deletion', () async {
      await chats.deleteChat(
        api,
        chatId: _chatId,
        forAll: false,
        accountId: _me,
      );

      expect(api.requests.single.$1, Opcode.chatDelete);
      expect(api.requests.single.$2['forAll'], isFalse);
    });

    test('clearing is one CHAT_CLEAR for me and nothing else', () async {
      final outcome = await chats.clearHistory(api, chatId: _chatId);

      expect(outcome, isA<ServerDone>());
      expect(api.requests.single.$1, Opcode.chatClear);
      expect(api.requests.single.$2, {
        'chatId': _chatId,
        'lastEventTime': 6000,
        'forAll': false,
      });
      expect(await AppDatabase.loadChat(_me, _chatId), isNotEmpty);
      expect(await storedIds(), isEmpty);
    });
  });

  group('history the peer erased', () {
    Map<String, Object> serverMessage(int id, int time) => {
      'id': id,
      'sender': _peer,
      'time': time,
      'text': 'синтетика $id',
    };

    int historyRequests() =>
        api.requests.where((r) => r.$1 == Opcode.chatHistory).length;

    Future<List<String>> fetchAndReconcile(
      List<Map<String, Object>> messages, {
      int count = 50,
      List<Map<String, Object>>? second,
    }) async {
      var answered = 0;
      api.reply = (opcode) => opcode == Opcode.chatHistory
          ? {'messages': answered++ == 0 ? messages : (second ?? messages)}
          : null;
      final page = await MessagesModule(
        api,
      ).fetchHistoryPage(_me, _chatId, count: count);
      return chats.reconcileDeletedFromFetch(_me, _chatId, page);
    }

    test('an empty history clears every cached message', () async {
      final removed = await fetchAndReconcile([]);

      expect(historyRequests(), 2);
      expect(removed.toSet(), {'811', '812', '813', '814', '815'});
      expect(await storedIds(), {'temp_1_1'});
    });

    test('an empty answer the next one contradicts deletes nothing', () async {
      final removed = await fetchAndReconcile(
        [],
        count: 2,
        second: [serverMessage(814, 4000), serverMessage(815, 5000)],
      );

      expect(historyRequests(), 2);
      expect(removed, isEmpty);
      expect(await storedIds(), hasLength(6));
    });

    test('an empty answer for an empty cache is not asked twice', () async {
      await AppDatabase.clearMessages(_me, _chatId);
      api.requests.clear();

      expect(await fetchAndReconcile([]), isEmpty);
      expect(historyRequests(), 1);
    });

    test(
      'a new message after the erase does not revive the old ones',
      () async {
        final removed = await fetchAndReconcile([serverMessage(900, 9000)]);

        expect(removed, hasLength(5));
        expect(await storedIds(), {'900', 'temp_1_1'});
      },
    );

    test('a full page leaves older cached messages alone', () async {
      final removed = await fetchAndReconcile([
        serverMessage(814, 4000),
        serverMessage(815, 5000),
      ], count: 2);

      expect(removed, isEmpty);
      expect(await storedIds(), hasLength(6));
    });

    test('a device clock days behind does not claim newer history', () async {
      const behind = 3 * Duration.millisecondsPerDay;
      final now = DateTime.now().millisecondsSinceEpoch;
      ServerClock.sync(now + behind, localNow: now);
      final recent = now + behind - 3600000;
      await AppDatabase.saveMessages([_stored('816', recent).toDbRow()]);
      api.reply = (opcode) {
        if (opcode != Opcode.chatHistory) return null;
        final from = api.requests.last.$2['from'] as int;
        return {
          'messages': [if (recent <= from) serverMessage(816, recent)],
        };
      };

      final page = await MessagesModule(api).fetchHistoryPage(_me, _chatId);
      final removed = await chats.reconcileDeletedFromFetch(_me, _chatId, page);

      expect(api.requests.last.$2['from'], greaterThan(recent));
      expect(page.window!.end, lessThan(api.requests.last.$2['from'] as int));
      expect(removed, isNot(contains('816')));
      expect(await storedIds(), contains('816'));
    });

    test('a refused history request deletes nothing', () async {
      api.reply = (opcode) => Packet(cmd: CmdType.notFound, opcode: opcode);
      final page = await MessagesModule(api).fetchHistoryPage(_me, _chatId);

      expect(
        await chats.reconcileDeletedFromFetch(_me, _chatId, page),
        isEmpty,
      );
      expect(await storedIds(), hasLength(6));
    });
  });
}
