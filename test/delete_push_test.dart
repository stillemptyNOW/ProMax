import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/token_storage.dart';
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

  @override
  Stream<Packet> get pushStream => pushes.stream;

  @override
  Stream<SessionState> get stateStream => states.stream;
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
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync(
      'synthetic_delete_push_test',
    );
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
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

  test('a chat the server marks removed leaves the visible list', () async {
    api.pushes.add(
      Packet(
        cmd: CmdType.push,
        opcode: Opcode.notifChat,
        payload: {
          'chat': {..._chat(), 'status': 'REMOVED'},
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await chats.pushesHandled;

    final rows = await AppDatabase.loadChat(_me, _chatId);
    expect(rows.single['in_list'], 2);
    expect(
      chats.chatsSnapshot().map((chat) => chat.id),
      isNot(contains(_chatId)),
    );
  });
}
