import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/local_read_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String directory;
  _Paths(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class _SilentApi extends Api {
  final requests = <Map<dynamic, dynamic>>[];

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    requests.add(payload);
    return Packet(cmd: CmdType.ok, payload: const {});
  }
}

const int _me = 3101;
const int _peer = 3102;
const int _chatId = -77001;

Map<String, dynamic> _snapshot({
  required int lastTime,
  required int unread,
  int myServerMark = 100,
}) => {
  'id': _chatId,
  'type': 'CHAT',
  'status': 'ACTIVE',
  'title': 'Synthetic watermark group',
  'participants': {'$_me': myServerMark, '$_peer': lastTime},
  'newMessages': unread,
  'lastMessage': {
    'id': lastTime,
    'time': lastTime,
    'sender': _peer,
    'text': 'synthetic text',
  },
};

CachedMessage _message(int time) => CachedMessage(
  id: '$time',
  accountId: _me,
  chatId: _chatId,
  senderId: _peer,
  text: 'synthetic text',
  time: time,
);

void main() {
  group('LocalReadState', () {
    test('viewing everything remembers how many server unreads were seen', () {
      final state = const LocalReadState().viewedUpTo(
        5000,
        serverMark: 100,
        displayedUnread: 40,
        remaining: 0,
      );
      expect(state.mark, 5000);
      expect(state.serverMark, 100);
      expect(state.serverUnread, 40);
      expect(state.seen, 40);
      expect(state.unreadFor(5000), 0);
      expect(state.withServer(serverUnread: 41).unreadFor(5100), 1);
      expect(state.withServer(serverUnread: 43).unreadFor(5300), 3);
    });

    test('scrolling part way keeps the rest unread', () {
      final state = const LocalReadState().viewedUpTo(
        4000,
        serverMark: 100,
        displayedUnread: 10,
        remaining: 4,
      );
      expect(state.seen, 6);
      expect(state.unreadFor(5000), 4);
      final further = state.viewedUpTo(
        5000,
        serverMark: 4000,
        displayedUnread: 4,
        remaining: 0,
      );
      expect(further.serverMark, 100);
      expect(further.seen, 10);
      expect(further.withServer(serverUnread: 11).unreadFor(5100), 1);
    });

    test('an older view never moves the watermark back', () {
      final state = const LocalReadState(
        mark: 5000,
        serverMark: 100,
        serverUnread: 3,
        seen: 3,
      );
      expect(
        identical(
          state.viewedUpTo(
            4000,
            serverMark: 100,
            displayedUnread: 0,
            remaining: 0,
          ),
          state,
        ),
        isTrue,
      );
    });

    test('the server catching up drops the local watermark', () {
      const state = LocalReadState(
        mark: 5000,
        serverMark: 100,
        serverUnread: 3,
        seen: 3,
      );
      expect(
        state.withServer(serverUnread: 0, serverMark: 5000).isActive,
        isFalse,
      );
      final moved = state.withServer(serverUnread: 2, serverMark: 3000);
      expect(moved.isActive, isTrue);
      expect(moved.serverMark, 3000);
      expect(moved.seen, isNull);
    });

    test('a newer message the server still counts is at least one unread', () {
      expect(
        localUnreadCount(
          serverUnread: 2,
          seen: 5,
          localMark: 500,
          lastMessageTime: 600,
        ),
        1,
      );
      expect(
        localUnreadCount(
          serverUnread: 0,
          seen: 5,
          localMark: 500,
          lastMessageTime: 600,
        ),
        0,
      );
    });

    test('survives a json round trip, including older entries', () {
      const state = LocalReadState(
        mark: 5000,
        serverMark: 100,
        serverUnread: 7,
        seen: 6,
      );
      expect(LocalReadState.fromJson(state.toJson()), state);
      expect(
        LocalReadState.fromJson({'mark': 5000, 'serverMark': 100}),
        const LocalReadState(mark: 5000, serverMark: 100),
      );
      expect(LocalReadState.fromJson('garbage'), const LocalReadState());
    });
  });

  group('"don\'t read" mode against the chat cache', () {
    late _SilentApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final directory = Directory.systemTemp.createTempSync(
        'promax_watermark_test',
      );
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      api = _SilentApi();
      ProMaxSettings.antiRead.value = true;
      addTearDown(() async {
        ProMaxSettings.antiRead.value = false;
        await api.dispose();
        await AppDatabase.close();
        PathProviderPlatform.instance = previousPaths;
        directory.deleteSync(recursive: true);
      });
      await AppDatabase.init();
      await AppDatabase.saveProfile(ProfileData.stub(_me));
    });

    test('one new message after reading counts as one even when most of the '
        'history was never cached', () async {
      await chats.cacheServerChat(_snapshot(lastTime: 5000, unread: 40), _me);
      await AppDatabase.saveMessages([
        _message(4900).toDbRow(),
        _message(5000).toDbRow(),
      ]);

      await chats.markRead(api, _me, _chatId, '5000', 5000);
      expect(api.requests, isEmpty);

      final fresh = await chats.cacheServerChat(
        _snapshot(lastTime: 5100, unread: 41),
        _me,
      );
      expect(fresh!.unreadCount, 1);
      expect(fresh.participants[_me], 5000);
    });

    test('reading part of the chat leaves exactly the rest unread', () async {
      await chats.cacheServerChat(_snapshot(lastTime: 5000, unread: 10), _me);

      await chats.markReadUpTo(api, _me, _chatId, '4000', 4000, remaining: 4);
      expect(api.requests, isEmpty);

      final fresh = await chats.cacheServerChat(
        _snapshot(lastTime: 5100, unread: 11),
        _me,
      );
      expect(fresh!.unreadCount, 5);
    });

    test(
      'reading on another device hands the count back to the server',
      () async {
        await chats.cacheServerChat(_snapshot(lastTime: 5000, unread: 3), _me);
        await chats.markRead(api, _me, _chatId, '5000', 5000);

        final fresh = await chats.cacheServerChat(
          _snapshot(lastTime: 5200, unread: 1, myServerMark: 5100),
          _me,
        );
        expect(fresh!.unreadCount, 1);
        expect((await LocalReadState.load(_me, _chatId)).isActive, isFalse);
      },
    );
  });
}
