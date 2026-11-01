import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/push/fkm_bridge.dart';
import 'package:promax/core/push/fkm_controller.dart';
import 'package:promax/core/push/notification_bridge.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/ignored_senders.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fkm = MethodChannel('io.github.stillemptynow.promax/fkm');
const _notifications = MethodChannel(
  'io.github.stillemptynow.promax/notifications',
);
const _localNotifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String directory;
  _Paths(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

class _PushApi extends Api {
  final pushes = StreamController<Packet>.broadcast();

  @override
  Stream<Packet> get pushStream => pushes.stream;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async => Packet(cmd: CmdType.ok, opcode: opcode, payload: const {});
}

const int _me = 820001;
const int _peer = 820333;
const int _ignored = 820999;
const int _dialog = _me ^ _peer;
const int _ignoredDialog = _me ^ _ignored;

Map<String, Object> _chat(int chatId, int peer) => {
  'id': chatId,
  'type': 'DIALOG',
  'status': 'ACTIVE',
  'participants': {'$_me': 1000, '$peer': 5000},
  'newMessages': 3,
  'lastMessage': {
    'id': 5000,
    'time': 5000,
    'sender': peer,
    'text': 'synthetic text',
  },
};

Packet _push(int chatId, int sender, int time) => Packet(
  cmd: CmdType.push,
  opcode: Opcode.notifMessage,
  payload: {
    'chatId': chatId,
    'message': {
      'id': time,
      'sender': sender,
      'time': time,
      'text': 'synthetic text $time',
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<dynamic, dynamic>> shown;
  late _PushApi api;
  late FkmController controller;

  setUpAll(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    _messenger.setMockMethodCallHandler(
      _localNotifications,
      (call) async => call.method == 'initialize' ? true : null,
    );
  });

  tearDownAll(
    () => _messenger.setMockMethodCallHandler(_localNotifications, null),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IgnoredSenders.instance.reset();
    shown = [];
    _messenger.setMockMethodCallHandler(_fkm, (call) async {
      if (call.method == 'showMessage') {
        shown.add((call.arguments as Map)['data'] as Map);
      }
      return call.method == 'isEnabled' ? true : null;
    });
    final directory = Directory.systemTemp.createTempSync(
      'promax_fkm_watermark_test',
    );
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    api = _PushApi();
    controller = FkmController.withBridge(
      FkmBridge.forTesting(isSupported: true),
    );
    ProMaxSettings.antiRead.value = true;
    addTearDown(() async {
      ProMaxSettings.antiRead.value = false;
      controller.dispose();
      await api.pushes.close();
      await api.dispose();
      Api.keepAliveInBackground = false;
      _messenger.setMockMethodCallHandler(_fkm, null);
      await AppDatabase.close();
      PathProviderPlatform.instance = previousPaths;
      directory.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(_me));
    await TokenStorage.setActiveAccount(_me);
    await chats.cacheServerChat(_chat(_dialog, _peer), _me);
    await chats.cacheServerChat(_chat(_ignoredDialog, _ignored), _me);
    await controller.init(api);
  });

  Future<void> deliver(Packet packet) async {
    api.pushes.add(packet);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  List<String> shownIds() => [for (final data in shown) '${data['msgid']}'];

  test(
    'messages already seen in "don\'t read" mode are not shown again',
    () async {
      await chats.markRead(api, _me, _dialog, '5000', 5000);

      await deliver(_push(_dialog, _peer, 4000));
      await deliver(_push(_dialog, _peer, 5000));
      expect(shown, isEmpty);

      await deliver(_push(_dialog, _peer, 6000));
      expect(shownIds(), ['6000']);
    },
  );

  test('the same message is shown only once', () async {
    await deliver(_push(_dialog, _peer, 6000));
    await deliver(_push(_dialog, _peer, 6000));
    expect(shownIds(), ['6000']);
  });

  test('the notification carries the "don\'t read" watermark so native drops '
      'messages the user already saw from the chat history', () async {
    await chats.markRead(api, _me, _dialog, '5000', 5000);

    await deliver(_push(_dialog, _peer, 6000));

    expect(shownIds(), ['6000']);
    expect(shown.single['seen'], '5000');
  });

  test('a message is not notified again after the engine restarts', () async {
    await deliver(_push(_dialog, _peer, 6000));
    controller.dispose();
    controller = FkmController.withBridge(
      FkmBridge.forTesting(isSupported: true),
    );
    await controller.init(api);

    await deliver(_push(_dialog, _peer, 6000));
    await deliver(_push(_dialog, _peer, 7000));

    expect(shownIds(), ['6000', '7000']);
  });

  test('reading part of a chat prunes the seen messages from its '
      'notification', () async {
    final calls = <MethodCall>[];
    NotificationBridge.instance.debugNative = true;
    _messenger.setMockMethodCallHandler(_notifications, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      NotificationBridge.instance.debugNative = false;
      _messenger.setMockMethodCallHandler(_notifications, null);
    });

    await chats.markReadUpTo(api, _me, _dialog, '4000', 4000, remaining: 1);
    await pumpEventQueue();

    expect(
      [
        for (final call in calls)
          if (call.method == 'pruneChat') call.arguments,
      ],
      [
        {'chatId': _dialog, 'seen': 4000},
      ],
    );
  });

  test('an ignored sender never reaches the notification shade', () async {
    await IgnoredSenders.instance.add(_me, _ignored);
    await deliver(_push(_ignoredDialog, _ignored, 7000));
    expect(shown, isEmpty);
  });
}
