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
import 'package:promax/core/storage/local_read_state.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _ActionApi extends Api {
  final requests = <({int opcode, Map<dynamic, dynamic> payload})>[];
  Future<void> Function()? duringAction;
  bool failAction = false;
  bool failReceipt = false;
  int epoch = 1;

  @override
  int get sessionEpoch => epoch;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    beforeSend?.call();
    requests.add((opcode: opcode, payload: Map.from(payload)));
    if (opcode == Opcode.chatMark) {
      if (failReceipt) throw const PacketError('Synthetic receipt failure');
      return Packet(cmd: CmdType.ok, payload: {});
    }
    await duringAction?.call();
    if (failAction) return Packet(cmd: CmdType.error, payload: {});
    return Packet(
      cmd: CmdType.ok,
      payload: {
        'message': {'id': '900'},
      },
    );
  }

  List<Map<dynamic, dynamic>> get receipts => [
    for (final request in requests)
      if (request.opcode == Opcode.chatMark) request.payload,
  ];
}

CachedMessage _message(int time, {int sender = 102}) => CachedMessage(
  id: '$time',
  accountId: 101,
  chatId: -301,
  senderId: sender,
  text: 'Synthetic action message',
  time: time,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ActionApi api;
  late MessagesModule messages;

  Future<void> configure({
    bool reaction = false,
    bool reply = false,
    bool send = false,
    bool antiRead = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('promax_anti_read', antiRead);
    await prefs.setBool('promax_read_on_reaction', reaction);
    await prefs.setBool('promax_read_on_reply', reply);
    await prefs.setBool('promax_read_on_send', send);
    await ProMaxSettings.load();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'synthetic_read_action_',
    );
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    api = _ActionApi();
    messages = MessagesModule(api);
    addTearDown(() async {
      await configure();
      ProMaxSettings.antiRead.value = false;
      await api.dispose();
      await AppDatabase.close();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(101));
    await TokenStorage.setActiveAccount(101);
    await chats.cacheServerChat({
      'id': -301,
      'type': 'CHAT',
      'status': 'ACTIVE',
      'title': 'Synthetic actions',
      'participants': {'101': 50, '102': 300},
      'newMessages': 3,
      'lastMessage': {
        'id': 300,
        'time': 300,
        'sender': 102,
        'text': 'Synthetic',
      },
    }, 101);
    await AppDatabase.saveMessages([
      for (final time in [100, 200, 300]) _message(time).toDbRow(),
    ]);
    await configure();
  });

  test('default anti-read never sends action receipts', () async {
    await messages.setReaction(-301, '100', '⭐');
    await messages.sendMessage(
      101,
      -301,
      'Synthetic reply',
      replyToMessageId: 200,
    );
    await messages.sendMessage(101, -301, 'Synthetic send');
    expect(api.receipts, isEmpty);
  });

  test(
    'reaction reads through its target and preserves newer local reads',
    () async {
      await configure(reaction: true);
      await chats.markReadUpTo(api, 101, -301, '200', 200, remaining: 1);
      final before = await LocalReadState.load(101, -301);
      final chatBefore = (await AppDatabase.loadChat(101, -301)).single;
      await messages.setReaction(-301, '100', '⭐');
      expect(api.receipts.single, {
        'type': 'READ_MESSAGE',
        'chatId': -301,
        'messageId': 100,
        'mark': 100,
      });
      expect(await LocalReadState.load(101, -301), before);
      expect(
        (await AppDatabase.loadChat(101, -301)).single['unread_count'],
        chatBefore['unread_count'],
      );
    },
  );

  test('reply acknowledges only the message being answered', () async {
    await configure(reply: true);
    await messages.sendMessage(
      101,
      -301,
      'Synthetic reply',
      replyToMessageId: 200,
    );
    expect(api.receipts.single['messageId'], 200);
    expect(api.receipts.single['mark'], 200);
  });

  test(
    'server acknowledgment preserves locally seen and newer unread messages',
    () async {
      await configure(reaction: true);
      await chats.markReadUpTo(api, 101, -301, '200', 200, remaining: 1);
      await messages.setReaction(-301, '100', '⭐');
      final fresh = await chats.cacheServerChat({
        'id': -301,
        'type': 'CHAT',
        'status': 'ACTIVE',
        'title': 'Synthetic actions',
        'participants': {'101': 100, '102': 400},
        'newMessages': 3,
        'lastMessage': {
          'id': 400,
          'time': 400,
          'sender': 102,
          'text': 'Synthetic',
        },
      }, 101);
      expect(fresh!.unreadCount, 2);
      expect(fresh.participants[101], 200);
      expect((await LocalReadState.load(101, -301)).serverMark, 100);
    },
  );

  test('send snapshots incoming messages before newer arrivals', () async {
    await configure(send: true);
    api.duringAction = () async =>
        AppDatabase.saveMessages([_message(400).toDbRow()]);
    await messages.sendMessage(101, -301, 'Synthetic send');
    expect(api.receipts.single['mark'], 300);
  });

  test('successful media sends use the same bounded send action', () async {
    await configure(send: true);
    await messages.sendStickerMessage(-301, 7);
    expect(api.receipts.single['mark'], 300);
  });

  test('failed actions and scheduled messages reveal no read state', () async {
    await configure(reaction: true, reply: true, send: true);
    api.failAction = true;
    await messages.setReaction(-301, '100', '⭐');
    await expectLater(
      messages.sendMessage(101, -301, 'Synthetic failed'),
      throwsException,
    );
    api.failAction = false;
    await messages.sendMessage(
      101,
      -301,
      'Synthetic scheduled',
      scheduledTime: 9000,
    );
    expect(api.receipts, isEmpty);
  });

  test(
    'foreign reply targets, own messages and reaction removal do not acknowledge',
    () async {
      await configure(reaction: true, reply: true);
      await AppDatabase.saveMessages([_message(400, sender: 101).toDbRow()]);
      await messages.setReaction(-301, '400', '⭐');
      await messages.cancelReaction(-301, '100');
      await messages.sendMessage(
        101,
        -301,
        'Synthetic foreign reply',
        replyToMessageId: 200,
        replySourceChatId: -302,
      );
      expect(api.receipts, isEmpty);
    },
  );

  test('switching accounts while sending prevents a later receipt', () async {
    await configure(send: true);
    api.duringAction = () => TokenStorage.setActiveAccount(202);
    await messages.sendMessage(101, -301, 'Synthetic account switch');
    expect(api.receipts, isEmpty);
  });

  test('changing session while sending prevents a later receipt', () async {
    await configure(send: true);
    api.duringAction = () async {
      api.epoch++;
    };
    await messages.sendMessage(101, -301, 'Synthetic session switch');
    expect(api.receipts, isEmpty);
  });

  test('a receipt error never turns a successful send into failure', () async {
    await configure(send: true);
    api.failReceipt = true;
    expect(
      await messages.sendMessage(101, -301, 'Synthetic successful'),
      '900',
    );
    expect(api.receipts, hasLength(1));
  });

  test('disabling the option during an action prevents its receipt', () async {
    await configure(send: true);
    api.duringAction = () => configure();
    await messages.sendMessage(101, -301, 'Synthetic canceled option');
    expect(api.receipts, isEmpty);
  });

  test('normal read mode never adds action receipts', () async {
    await configure(reaction: true, reply: true, send: true, antiRead: false);
    await messages.setReaction(-301, '100', '⭐');
    await messages.sendMessage(101, -301, 'Synthetic normal mode');
    expect(api.receipts, isEmpty);
  });
}
