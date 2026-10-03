import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/api.dart';
import 'package:komet/backend/modules/chats.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/core/config/komet_settings.dart';
import 'package:komet/core/protocol/packet.dart';
import 'package:komet/core/storage/app_database.dart';
import 'package:komet/core/storage/local_read_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String directory;
  _Paths(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class _ReadApi extends Api {
  final requests = <Map<dynamic, dynamic>>[];

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    requests.add(payload);
    return Packet(cmd: CmdType.ok, payload: {'unread': 1});
  }
}

Map<String, dynamic> _snapshot({int lastTime = 500, int unread = 2}) => {
  'id': -301,
  'type': 'CHAT',
  'status': 'ACTIVE',
  'title': 'Synthetic group',
  'participants': {'101': 100, '102': 100},
  'newMessages': unread,
  'lastMessage': {
    'id': lastTime,
    'time': lastTime,
    'sender': 102,
    'text': 'Synthetic message',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ReadApi api;

  setUp(() async {
    final directory = Directory.systemTemp.createTempSync('promax_read_test');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    api = _ReadApi();
    KometSettings.antiRead.value = true;
    addTearDown(() async {
      KometSettings.antiRead.value = false;
      await api.dispose();
      await AppDatabase.close();
      PathProviderPlatform.instance = previousPaths;
      directory.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(101));
    await chats.cacheServerChat(_snapshot(), 101);
    await AppDatabase.saveMessages([
      for (final time in [300, 500])
        CachedMessage(
          id: '$time',
          accountId: 101,
          chatId: -301,
          senderId: 102,
          text: 'Synthetic message',
          time: time,
        ).toDbRow(),
    ]);
  });

  test(
    'viewed messages remain read across database reopen and server sync',
    () async {
      await chats.markRead(api, 101, -301, '500', 500);
      expect(api.requests, isEmpty);
      await AppDatabase.close();
      await AppDatabase.init();
      expect((await LocalReadState.load(101, -301)).mark, 500);
      final old = await chats.cacheServerChat(_snapshot(), 101);
      expect(old!.unreadCount, 0);
      expect(old.participants[101], 500);
      final fresh = await chats.cacheServerChat(
        _snapshot(lastTime: 600, unread: 3),
        101,
      );
      expect(fresh!.unreadCount, 1);
      expect((await LocalReadState.load(202, -301)).mark, 0);
    },
  );

  test('an explicit mark unread resets the local read override', () async {
    await chats.markRead(api, 101, -301, '500', 500);
    expect(await chats.markUnread(api, 101, -301, 500), 1);
    expect(api.requests.single['type'], 'SET_AS_UNREAD');
    expect((await LocalReadState.load(101, -301)).mark, 0);
    final fresh = await chats.cacheServerChat(_snapshot(unread: 1), 101);
    expect(fresh!.unreadCount, 1);
  });
}
