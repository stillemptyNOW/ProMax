import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/ignored_senders.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String directory;
  _Paths(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class _PushApi extends Api {
  final pushes = StreamController<Packet>.broadcast();
  final states = StreamController<SessionState>.broadcast();
  final requests = <(int, Map<dynamic, dynamic>)>[];

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
    requests.add((opcode, payload));
    return Packet(cmd: CmdType.ok, opcode: opcode, payload: const {});
  }
}

const int _me = 710001;
const int _ignored = 710777;
const int _friend = 710555;
const int _ignoredDialog = _me ^ _ignored;
const int _friendDialog = _me ^ _friend;
const int _groupId = -710900;

Map<String, Object> _dialog(int chatId, int peer, {int unread = 0}) => {
  'id': chatId,
  'type': 'DIALOG',
  'status': 'ACTIVE',
  'participants': {'$_me': 1000, '$peer': 1000},
  'newMessages': unread,
  'lastMessage': {
    'id': 1000,
    'time': 1000,
    'sender': _me,
    'text': 'synthetic own text',
  },
};

Packet _incoming(int chatId, int sender, int id, {int unread = 1}) => Packet(
  cmd: CmdType.push,
  opcode: Opcode.notifMessage,
  payload: {
    'chatId': chatId,
    'unread': unread,
    'message': {
      'id': id,
      'sender': sender,
      'time': id,
      'text': 'synthetic incoming $id',
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IgnoredSenders', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      IgnoredSenders.instance.reset();
    });

    test('keeps a separate list per account and persists it', () async {
      final store = IgnoredSenders.instance;
      expect(await store.add(_me, _ignored), isTrue);
      expect(await store.add(_me, _ignored), isFalse);
      expect(await store.add(_me, _me), isFalse);
      expect(await store.add(_friend, _ignored), isTrue);
      expect(store.of(_me), [_ignored]);

      store.reset();
      await store.load();
      expect(store.isIgnored(_me, _ignored), isTrue);
      expect(store.isIgnored(_friend, _ignored), isTrue);
      expect(store.isIgnored(_me, _friend), isFalse);

      expect(await store.remove(_friend, _ignored), isTrue);
      expect(store.isIgnored(_friend, _ignored), isFalse);
      expect(store.isIgnored(_me, _ignored), isTrue);
    });

    test('applies to private dialogs only', () async {
      final store = IgnoredSenders.instance;
      await store.add(_me, _ignored);
      expect(
        store.hidesFromDialog(
          accountId: _me,
          chatId: _ignoredDialog,
          senderId: _ignored,
        ),
        isTrue,
      );
      expect(
        store.hidesFromDialog(
          accountId: _me,
          chatId: _groupId,
          senderId: _ignored,
        ),
        isFalse,
      );
      expect(
        store.hidesFromDialog(
          accountId: _me,
          chatId: 12345,
          senderId: _ignored,
          isDialog: true,
        ),
        isTrue,
      );
      expect(
        store.hidesFromDialog(
          accountId: _me,
          chatId: _ignoredDialog,
          senderId: _me,
        ),
        isFalse,
      );
      expect(store.ignoredPeer(_me, _ignoredDialog), _ignored);
      expect(store.ignoredPeer(_me, _friendDialog), isNull);
      expect(store.ignoredPeer(_me, _groupId), isNull);
    });

    test('parses only plain numeric ids', () {
      expect(IgnoredSenders.parseUserId(' 710777 '), _ignored);
      expect(IgnoredSenders.parseUserId('0'), isNull);
      expect(IgnoredSenders.parseUserId('-5'), isNull);
      expect(IgnoredSenders.parseUserId('12a'), isNull);
      expect(IgnoredSenders.parseUserId(''), isNull);
      expect(IgnoredSenders.parseUserId('99999999999999999'), isNull);
    });

    test('ignores broken stored data', () {
      expect(IgnoredSenders.decode('not json'), isEmpty);
      expect(
        IgnoredSenders.decode(
          '{"$_me":[$_ignored,"x",-1,$_me],"bad":[1],"$_friend":"x"}',
        ),
        {
          _me: {_ignored},
        },
      );
      expect(
        IgnoredSenders.decode(
          IgnoredSenders.encode({
            _me: {_ignored, _friend},
          }),
        ),
        {
          _me: {_ignored, _friend},
        },
      );
    });
  });

  group('incoming traffic from an ignored sender', () {
    final api = _PushApi();

    setUpAll(() => chats.attachGlobalPushHandlers(api));

    tearDownAll(() async {
      await api.pushes.close();
      await api.states.close();
      await api.dispose();
    });

    setUp(() async {
      api.requests.clear();
      SharedPreferences.setMockInitialValues({});
      IgnoredSenders.instance.reset();
      final directory = Directory.systemTemp.createTempSync(
        'promax_ignored_senders_test',
      );
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      addTearDown(() async {
        ProMaxSettings.antiRead.value = false;
        await AppDatabase.close();
        PathProviderPlatform.instance = previousPaths;
        directory.deleteSync(recursive: true);
      });
      await AppDatabase.init();
      await AppDatabase.saveProfile(ProfileData.stub(_me));
      await TokenStorage.setActiveAccount(_me);
      await IgnoredSenders.instance.add(_me, _ignored);
      await chats.cacheServerChat(_dialog(_ignoredDialog, _ignored), _me);
      await chats.cacheServerChat(_dialog(_friendDialog, _friend), _me);
    });

    Future<void> deliver(Packet packet) async {
      api.pushes.add(packet);
      await pumpEventQueue();
      await chats.pushesHandled;
    }

    Future<Set<String>> stored(int chatId) async => {
      for (final row in await AppDatabase.loadMessages(_me, chatId))
        row['id'].toString(),
    };

    Future<CachedChat> chat(int chatId) async =>
        CachedChat.fromDbRow((await AppDatabase.loadChat(_me, chatId)).first);

    test(
      'is dropped, deleted for me on the server and leaves the chat as is',
      () async {
        await deliver(_incoming(_ignoredDialog, _ignored, 2000));

        expect(await stored(_ignoredDialog), isEmpty);
        final hidden = await chat(_ignoredDialog);
        expect(hidden.unreadCount, 0);
        expect(hidden.lastMsgId, 1000);
        expect(hidden.lastEventTime, isNot(2000));
        final deletions = [
          for (final (opcode, payload) in api.requests)
            if (opcode == Opcode.msgDelete) payload,
        ];
        expect(deletions, hasLength(1));
        expect(deletions.single['chatId'], _ignoredDialog);
        expect(deletions.single['messageIds'], [2000]);
        expect(deletions.single['forMe'], isTrue);
        expect(api.requests.where((r) => r.$1 == Opcode.chatMark), isEmpty);
      },
    );

    test('from other people still arrives', () async {
      await deliver(_incoming(_friendDialog, _friend, 2100));

      expect(await stored(_friendDialog), {'2100'});
      expect((await chat(_friendDialog)).unreadCount, 1);
      expect(api.requests.where((r) => r.$1 == Opcode.msgDelete), isEmpty);
    });

    test('a server snapshot does not raise the hidden dialog', () async {
      final snapshot = _dialog(_ignoredDialog, _ignored, unread: 3)
        ..['lastMessage'] = {
          'id': 3000,
          'time': 3000,
          'sender': _ignored,
          'text': 'synthetic hidden text',
        };
      final cached = await chats.cacheServerChat(snapshot, _me);

      expect(cached!.unreadCount, 0);
      expect(cached.lastMsgId, 1000);
      expect(cached.lastMsgSenderId, _me);
      await pumpEventQueue();
      expect(
        api.requests
            .where((r) => r.$1 == Opcode.msgDelete)
            .single
            .$2['messageIds'],
        [3000],
      );
    });

    test('never sends a read mark for the hidden dialog', () async {
      await chats.cacheServerChat(
        _dialog(_ignoredDialog, _ignored, unread: 1),
        _me,
      );
      await chats.cacheServerChat(
        _dialog(_friendDialog, _friend, unread: 1),
        _me,
      );

      await chats.markRead(api, _me, _ignoredDialog, '1000', 1000);
      expect(api.requests.where((r) => r.$1 == Opcode.chatMark), isEmpty);

      await chats.markRead(api, _me, _friendDialog, '1000', 1000);
      expect(api.requests.where((r) => r.$1 == Opcode.chatMark), hasLength(1));
    });
  });
}
