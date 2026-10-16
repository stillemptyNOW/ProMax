import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/backend/modules/outbox.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SyntheticPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _RecordingApi extends Api {
  SessionState currentState = SessionState.online;
  final pushes = StreamController<Packet>.broadcast();
  final changes = StreamController<SessionState>.broadcast();
  final sentCids = <Object?>[];
  Future<Packet> Function(Map<dynamic, dynamic>)? responder;

  @override
  SessionState get state => currentState;

  @override
  int get sessionEpoch => 1;

  @override
  Stream<SessionState> get stateStream => changes.stream;

  @override
  Stream<Packet> get pushStream => pushes.stream;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) {
    beforeSend?.call();
    sentCids.add((payload['message'] as Map)['cid']);
    final handler = responder;
    if (handler != null) return handler(payload);
    return Future.value(
      Packet(
        cmd: CmdType.ok,
        payload: {
          'message': {'id': 7000 + sentCids.length},
        },
      ),
    );
  }
}

const int _me = 4101;
const int _chatId = 4303;

CachedMessage _outgoing(
  String id,
  String status, {
  String? text = 'Синтетический текст',
  Map<String, dynamic>? payload,
}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: _chatId,
  senderId: _me,
  text: text,
  time: 1000,
  status: status,
  payload: payload,
);

Future<String?> _statusOf(String id) async =>
    (await AppDatabase.loadMessage(_me, _chatId, id))?['status'] as String?;

Future<void> _eventually(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _RecordingApi();
  final outbox = OutboxService.instance;

  setUpAll(() {
    outbox.init(api, MessagesModule(api));
    chats.attachGlobalPushHandlers(api);
  });

  tearDownAll(() async {
    await api.pushes.close();
    await api.changes.close();
    await api.dispose();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('synthetic_resend');
    final previousProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(_me));
    await AppDatabase.saveChats([
      {
        'id': _chatId,
        'account_id': _me,
        'type': 'DIALOG',
        'title': 'Synthetic dialog',
        'cached_at': 0,
        'participants': '{}',
      },
    ]);
    await TokenStorage.setActiveAccount(_me);
    api.currentState = SessionState.online;
    api.sentCids.clear();
    api.responder = null;
    addTearDown(() async {
      await AppDatabase.close();
      PathProviderPlatform.instance = previousProvider;
      await directory.delete(recursive: true);
    });
  });

  test('a queued message is resent with its original cid', () async {
    await AppDatabase.saveMessages([
      _outgoing('temp_1_1', 'pending', payload: {'cid': -555}).toDbRow(),
    ]);

    await outbox.flush();

    expect(api.sentCids, [-555]);
    expect(await AppDatabase.loadPendingMessages(_me), isEmpty);
  });

  test('a legacy row keeps the cid it was first sent with', () async {
    await AppDatabase.saveMessages([
      _outgoing('temp_1_2', 'pending').toDbRow(),
    ]);
    api.responder = (_) {
      api.responder = null;
      return Future.error(TimeoutException('synthetic timeout'));
    };

    await outbox.flush();
    expect(outbox.retryScheduled, isTrue);
    await outbox.flush();

    expect(api.sentCids, hasLength(2));
    expect(api.sentCids.first, isA<int>());
    expect(api.sentCids.last, api.sentCids.first);
    expect(outbox.retryScheduled, isFalse);
  });

  test('sends interrupted by a killed app are settled on start', () async {
    await AppDatabase.saveMessages([
      _outgoing('temp_2_1', 'sending').toDbRow(),
      _outgoing(
        'temp_2_2',
        'sending',
        text: null,
        payload: {
          'attaches': [
            {'_type': 'PHOTO', 'baseUrl': 'https://example.invalid/p.jpg'},
          ],
        },
      ).toDbRow(),
    ]);
    api.currentState = SessionState.disconnected;

    await outbox.recoverInterruptedSends();

    expect(await _statusOf('temp_2_1'), 'pending');
    expect(await _statusOf('temp_2_2'), 'error');
  });

  test('retry puts a failed message back into the queue', () async {
    await AppDatabase.saveMessages([
      _outgoing('temp_3_1', 'error', payload: {'cid': -777}).toDbRow(),
    ]);

    expect(await outbox.retry(_me, _chatId, 'temp_3_1'), isTrue);
    await _eventually(() async => api.sentCids.isNotEmpty);
    await _eventually(() async => await _statusOf('temp_3_1') == null);

    expect(api.sentCids, [-777]);
    expect(await outbox.retry(_me, _chatId, 'temp_missing'), isFalse);
  });

  test(
    'our own echo replaces the unsent copy instead of duplicating it',
    () async {
      api.currentState = SessionState.disconnected;
      await AppDatabase.saveMessages([
        _outgoing('temp_4_1', 'pending', payload: {'cid': -888}).toDbRow(),
      ]);
      final sentEvent = chats.messageEvents
          .where((event) => event is MessageSentEvent)
          .cast<MessageSentEvent>()
          .first;

      api.pushes.add(
        Packet(
          cmd: CmdType.push,
          opcode: Opcode.notifMessage,
          payload: {
            'chatId': _chatId,
            'message': {
              'id': 9100,
              'cid': -888,
              'sender': _me,
              'text': 'Синтетический текст',
              'time': 2000,
            },
          },
        ),
      );
      final event = await sentEvent.timeout(const Duration(seconds: 5));
      await chats.pushesHandled;

      expect(event.tempId, 'temp_4_1');
      expect(event.message.id, '9100');
      expect(await AppDatabase.loadMessage(_me, _chatId, 'temp_4_1'), isNull);
      expect(await _statusOf('9100'), 'sent');
      expect(await AppDatabase.loadPendingMessages(_me), isEmpty);
    },
  );
}
