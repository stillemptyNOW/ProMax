import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/account/account_models.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SyntheticPathProvider(this.directory);

  final String directory;

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

const int _me = 5101;
const int _chatId = 5303;

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
    final directory = Directory.systemTemp.createTempSync('synthetic_pushes');
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
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
      'lastEventTime': 10,
      'participants': {'$_me': 0, '6101': 0},
    }, _me);
  });

  Future<void> push(int opcode, Map<String, Object?> payload) async {
    api.pushes.add(Packet(cmd: CmdType.push, opcode: opcode, payload: payload));
    await pumpEventQueue();
    await chats.pushesHandled;
  }

  test('own reaction from another device is applied', () async {
    await AppDatabase.saveMessages([
      CachedMessage(
        id: '61',
        accountId: _me,
        chatId: _chatId,
        senderId: 6101,
        text: 'синтетика',
        time: 5,
        payload: const {
          'reactionInfo': {
            'counters': [
              {'reaction': '👍', 'count': 1},
            ],
            'totalCount': 1,
          },
        },
      ).toDbRow(),
    ]);

    await push(Opcode.notifMsgYouReacted, {
      'chatId': _chatId,
      'messageId': '61',
      'reaction': '🔥',
    });
    var row = await AppDatabase.loadMessage(_me, _chatId, '61');
    var info = (jsonDecode(row!['payload'] as String) as Map)['reactionInfo'];
    expect(info['yourReaction'], '🔥');
    expect(info['totalCount'], 1);

    await push(Opcode.notifMsgYouReacted, {
      'chatId': _chatId,
      'messageId': '61',
      'reaction': null,
    });
    row = await AppDatabase.loadMessage(_me, _chatId, '61');
    info = (jsonDecode(row!['payload'] as String) as Map)['reactionInfo'];
    expect(info.containsKey('yourReaction'), isFalse);
  });

  test('a config push updates the saved privacy settings', () async {
    await AppDatabase.savePrivacyConfig(_me, PrivacyConfig.empty().toJson());

    await push(Opcode.notifConfig, {
      'config': {
        'user': {
          'CHATS_PUSH_NOTIFICATION': 'OFF',
          'SEARCH_BY_PHONE': 'CONTACTS',
        },
      },
    });

    final saved = PrivacyConfig.fromJson(
      (await AppDatabase.getPrivacyConfig(_me))!,
    );
    expect(saved.chatsPushNotification, 'OFF');
    expect(saved.searchByPhone, 'CONTACTS');
    expect(saved.incomingCall, PrivacyConfig.empty().incomingCall);
  });

  test('reaction values are read from every known shape', () {
    expect(ChatsModule.ownReactionOf({'yourReaction': '❤️'}), '❤️');
    expect(
      ChatsModule.ownReactionOf({
        'reaction': {'reaction': '😂'},
      }),
      '😂',
    );
    expect(
      ChatsModule.ownReactionOf({
        'reactionInfo': {'yourReaction': '👍'},
      }),
      '👍',
    );
    expect(ChatsModule.ownReactionOf({'reaction': ''}), isNull);
  });
}
