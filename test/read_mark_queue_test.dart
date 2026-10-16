import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/read_mark_queue.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FlakyApi extends Api {
  SessionState currentState = SessionState.disconnected;
  final changes = StreamController<SessionState>.broadcast();
  final sent = <int>[];
  Object? failure;

  @override
  SessionState get state => currentState;

  @override
  Stream<SessionState> get stateStream => changes.stream;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    if (currentState != SessionState.online) {
      throw StateError('Нет соединения (CHAT_MARK)');
    }
    final error = failure;
    if (error != null) throw error;
    sent.add(payload['mark'] as int);
    return Packet(cmd: CmdType.ok, payload: const {});
  }
}

ReadMark _mark(int chatId, int mark) =>
    ReadMark(accountId: 31, chatId: chatId, messageId: mark * 10, mark: mark);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FlakyApi api;
  late ReadMarkQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TokenStorage.setActiveAccount(31);
    api = _FlakyApi();
    queue = ReadMarkQueue();
    queue.attach(api);
  });

  tearDown(() async {
    await queue.detach();
    await api.changes.close();
  });

  Future<void> goOnline() async {
    api.currentState = SessionState.online;
    api.changes.add(SessionState.online);
    await pumpEventQueue();
    await queue.flush();
  }

  test('a read mark made offline reaches the server once online', () async {
    await queue.submit(api, _mark(5, 100));
    await queue.submit(api, _mark(5, 120));
    expect(api.sent, isEmpty);
    expect(queue.pending.single.mark, 120);

    await goOnline();

    expect(api.sent, [120]);
    expect(queue.pending, isEmpty);
  });

  test('queued marks survive a restart', () async {
    await queue.submit(api, _mark(6, 200));
    final restarted = ReadMarkQueue()..attach(api);
    addTearDown(restarted.detach);
    await restarted.flush();
    expect(restarted.pending.map((m) => m.mark), [200]);

    api.currentState = SessionState.online;
    await restarted.flush();
    expect(api.sent, [200]);
  });

  test('a refused mark is dropped, a timeout is kept', () async {
    api.currentState = SessionState.online;
    api.failure = TimeoutException('synthetic');
    await queue.submit(api, _mark(7, 300));
    expect(queue.pending, hasLength(1));

    api.failure = const PacketError('synthetic refusal');
    await queue.flush();
    expect(queue.pending, isEmpty);
  });
}
