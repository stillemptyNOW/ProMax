import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/chat_activity_store.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
const int _chatId = 900401;
const int _alice = 900501;
const Duration _typed = Duration(milliseconds: 60);

Packet _incoming(String id, {String text = 'Синтетический ответ'}) => Packet(
  cmd: CmdType.push,
  opcode: Opcode.notifMessage,
  payload: {
    'chatId': _chatId,
    'message': {
      'id': id,
      'time': 1000,
      'type': 'USER',
      'sender': _alice,
      'text': text,
      'attaches': const [],
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _PushOnlyApi();
  final activity = ChatActivityStore.instance;

  setUpAll(() => chats.attachGlobalPushHandlers(api));

  tearDownAll(() async {
    await api.pushes.close();
    await api.states.close();
    await api.dispose();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync(
      'synthetic_typing_time_push_test',
    );
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
      activity.clearChat(_chatId);
      ProMaxSettings.showTypingTime.value = false;
      await AppDatabase.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(_me));
    await TokenStorage.setActiveAccount(_me);
    await chats.cacheServerChat({
      'id': _chatId,
      'type': 'DIALOG',
      'status': 'ACTIVE',
      'participants': {'$_me': 0, '$_alice': 0},
    }, _me);
    ProMaxSettings.showTypingTime.value = true;
  });

  Future<int?> typingMsOfDelivered(Packet packet) async {
    final added = chats.messageEvents
        .where((event) => event is MessageAddedEvent)
        .cast<MessageAddedEvent>()
        .first;
    api.pushes.add(packet);
    return (await added).message.typingMs;
  }

  test('сообщение после «печатает» получает насчитанное время', () async {
    activity.mark(_chatId, _alice, ChatActivity.typing);
    await Future<void>.delayed(_typed);

    final typingMs = await typingMsOfDelivered(_incoming('7201'));

    expect(typingMs, greaterThanOrEqualTo(_typed.inMilliseconds));
    final row = await AppDatabase.loadMessage(_me, _chatId, '7201');
    expect(row!['typing_ms'], typingMs);
  });

  test('сообщение без «печатает» остаётся без времени', () async {
    expect(await typingMsOfDelivered(_incoming('7202')), isNull);
  });

  test('сообщение без текста не забирает отсчёт', () async {
    activity.mark(_chatId, _alice, ChatActivity.typing);

    expect(await typingMsOfDelivered(_incoming('7203', text: '')), isNull);
    expect(activity.takeTypingTime(_chatId, _alice), isNotNull);
  });

  test('с выключенной настройкой время не считается', () async {
    ProMaxSettings.showTypingTime.value = false;
    activity.mark(_chatId, _alice, ChatActivity.typing);

    expect(await typingMsOfDelivered(_incoming('7204')), isNull);
  });
}
