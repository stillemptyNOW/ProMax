import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart' show CachedMessage;
import 'package:promax/backend/modules/read_receipts.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/read_receipt.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:promax/core/utils/server_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
const int _chatId = 900801;
const int _peer = 900901;
const int _stranger = 900902;
const int _sessionStart = 500;

CachedMessage _message(
  String id,
  int time, {
  int sender = _me,
  bool deleted = false,
  bool control = false,
}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: _chatId,
  senderId: sender,
  time: time,
  isControl: control,
  deleted: deleted,
);

Map<String, Object> _chat({int peerMark = 0, bool withPeer = true}) => {
  'id': _chatId,
  'type': 'DIALOG',
  'status': 'ACTIVE',
  'lastEventTime': 9000,
  'newMessages': 0,
  'participants': {'$_me': 0, if (withPeer) '$_peer': peerMark},
};

Packet _mark(int userId, int mark, {bool setAsUnread = false}) => Packet(
  cmd: CmdType.push,
  opcode: Opcode.notifMark,
  payload: {
    'chatId': _chatId,
    'userId': userId,
    'mark': mark,
    if (setAsUnread) 'setAsUnread': true,
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _PushOnlyApi();
  late Directory directory;

  setUpAll(() => chats.attachGlobalPushHandlers(api));

  tearDownAll(() async {
    await api.pushes.close();
    await api.states.close();
    await api.dispose();
  });

  Future<void> seed({int peerMark = 0, bool withPeer = true}) async {
    await chats.cacheServerChat(
      _chat(peerMark: peerMark, withPeer: withPeer),
      _me,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ReadReceipts.instance.resetForTest();
    ServerClock.resetForTest();
    chats.beginReadSession(_sessionStart);
    directory = Directory.systemTemp.createTempSync('synthetic_read_receipts');
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
      ReadReceipts.instance.resetForTest();
      ServerClock.resetForTest();
      await AppDatabase.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(_me));
    await TokenStorage.setActiveAccount(_me);
  });

  Future<void> deliver(Packet packet) async {
    api.pushes.add(packet);
    await Future<void>.delayed(Duration.zero);
    await chats.pushesHandled;
  }

  MessageReadState stateOf(
    int time, {
    int? mark,
    int? replyTime,
    int userId = _peer,
  }) => ReadReceipts.instance.stateFor(
    accountId: _me,
    chatId: _chatId,
    userId: userId,
    mark: mark,
    messageTime: time,
    replyTime: replyTime,
  );

  Future<int?> storedPeerMark() async {
    final rows = await chats.getChat(_me, _chatId);
    return rows.first.participants[_peer];
  }

  group('resolve', () {
    const receipt = ReadReceipt(
      userId: _peer,
      prevMark: 2000,
      mark: 5000,
      readAt: 7000,
    );

    test('a missing mark hides the line', () {
      expect(
        ReadReceipts.resolve(
          mark: null,
          messageTime: 3000,
          receipts: const [receipt],
        ),
        MessageReadState.hidden,
      );
    });

    test('a mark below the message means not read', () {
      expect(
        ReadReceipts.resolve(
          mark: 2999,
          messageTime: 3000,
          receipts: const [receipt],
        ),
        MessageReadState.unread,
      );
    });

    test('a covering receipt gives the exact time', () {
      expect(
        ReadReceipts.resolve(
          mark: 5000,
          messageTime: 3000,
          receipts: const [receipt],
        ),
        const MessageReadState.exact(7000),
      );
    });

    test('a message at the previous mark is not covered', () {
      expect(
        ReadReceipts.resolve(
          mark: 5000,
          messageTime: 2000,
          receipts: const [receipt],
        ),
        MessageReadState.unknown,
      );
    });

    test('a read time before the message is clamped to the message', () {
      expect(
        ReadReceipts.resolve(
          mark: 5000,
          messageTime: 4000,
          receipts: const [
            ReadReceipt(
              userId: _peer,
              prevMark: 2000,
              mark: 5000,
              readAt: 3500,
            ),
          ],
        ),
        const MessageReadState.exact(4000),
      );
    });

    test('a later reply bounds an unknown read', () {
      expect(
        ReadReceipts.resolve(
          mark: 6000,
          messageTime: 1000,
          receipts: const [receipt],
          replyTime: 1500,
        ),
        const MessageReadState.atMost(1500),
      );
    });

    test('a reply earlier than the push time tightens it', () {
      expect(
        ReadReceipts.resolve(
          mark: 5000,
          messageTime: 3000,
          receipts: const [receipt],
          replyTime: 4000,
        ),
        const MessageReadState.atMost(4000),
      );
    });

    test('a reply after the exact time does not replace it', () {
      expect(
        ReadReceipts.resolve(
          mark: 5000,
          messageTime: 3000,
          receipts: const [receipt],
          replyTime: 8000,
        ),
        const MessageReadState.exact(7000),
      );
    });
  });

  test('a live mark push records when the peer read', () async {
    await seed();
    await ReadReceipts.instance.preload(_me, _chatId);
    final before = DateTime.now().millisecondsSinceEpoch;
    await deliver(_mark(_peer, 3000));
    final after = DateTime.now().millisecondsSinceEpoch;

    expect(await storedPeerMark(), 3000);
    for (final time in [1000, 3000]) {
      final state = stateOf(time, mark: 3000);
      expect(state.kind, MessageReadKind.exact);
      expect(state.at, inInclusiveRange(before, after));
    }
    expect(stateOf(4000, mark: 3000), MessageReadState.unread);
  });

  test('a second push leaves earlier messages with their time', () async {
    await seed();
    await ReadReceipts.instance.preload(_me, _chatId);
    await deliver(_mark(_peer, 3000));
    final first = stateOf(2000, mark: 3000);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await deliver(_mark(_peer, 6000));

    expect(stateOf(2000, mark: 6000), first);
    final second = stateOf(5000, mark: 6000);
    expect(second.kind, MessageReadKind.exact);
    expect(second.at, greaterThan(first.at!));
  });

  test('a mark learned from sync stays without a time', () async {
    await seed(peerMark: 3000);
    await ReadReceipts.instance.preload(_me, _chatId);

    expect(stateOf(2000, mark: 3000), MessageReadState.unknown);

    await deliver(_mark(_peer, 6000));

    expect(stateOf(2000, mark: 6000), MessageReadState.unknown);
    expect(stateOf(5000, mark: 6000).kind, MessageReadKind.exact);
  });

  test('receipts survive a restart through the database', () async {
    await seed();
    await deliver(_mark(_peer, 3000));
    ReadReceipts.instance.resetForTest();
    expect(ReadReceipts.instance.isLoaded(_me, _chatId), isFalse);

    await ReadReceipts.instance.preload(_me, _chatId);

    expect(stateOf(3000, mark: 3000).kind, MessageReadKind.exact);
  });

  test('an unread request and own reads are not recorded', () async {
    await seed();
    await ReadReceipts.instance.preload(_me, _chatId);
    await deliver(_mark(_peer, 3000, setAsUnread: true));
    await deliver(_mark(_me, 3000));

    expect(await AppDatabase.loadReadReceipts(_me, _chatId), isEmpty);
    expect(stateOf(3000, mark: 0), MessageReadState.unread);
  });

  test('a reader unknown to the chat is timed only after the login', () async {
    await seed(withPeer: false);
    chats.beginReadSession(2000);
    await deliver(_mark(_stranger, 3000));

    expect(
      stateOf(1500, mark: 3000, userId: _stranger),
      MessageReadState.unknown,
    );
    expect(
      stateOf(2500, mark: 3000, userId: _stranger).kind,
      MessageReadKind.exact,
    );
  });

  test('reads made while offline get no invented time', () async {
    api.states.add(SessionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    await seed(peerMark: 1000);
    chats.beginReadSession(4000);
    await deliver(_mark(_peer, 6000));

    expect(stateOf(2000, mark: 6000), MessageReadState.unknown);
    expect(stateOf(3500, mark: 6000), MessageReadState.unknown);
    expect(stateOf(5000, mark: 6000).kind, MessageReadKind.exact);
  });

  test('a fresh chat after the login confirms the previous mark', () async {
    api.states.add(SessionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    await seed(peerMark: 1000);
    chats.beginReadSession(4000);
    await chats.cacheServerChat(_chat(peerMark: 3000), _me);
    await deliver(_mark(_peer, 6000));

    expect(stateOf(2000, mark: 6000), MessageReadState.unknown);
    expect(stateOf(3500, mark: 6000).kind, MessageReadKind.exact);
  });

  test('a push while disconnected moves the mark without a time', () async {
    await seed();
    api.states.add(SessionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    await deliver(_mark(_peer, 3000));

    expect(await storedPeerMark(), 3000);
    expect(await AppDatabase.loadReadReceipts(_me, _chatId), isEmpty);
  });

  test('a stale lower mark does not move the base back', () async {
    await seed();
    await ReadReceipts.instance.preload(_me, _chatId);
    await deliver(_mark(_peer, 3000));
    final first = stateOf(2500, mark: 3000);
    await deliver(_mark(_peer, 2000));

    expect(await storedPeerMark(), 3000);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await deliver(_mark(_peer, 6000));

    expect(stateOf(2500, mark: 6000), first);
    expect(await AppDatabase.loadReadReceipts(_me, _chatId), hasLength(2));
  });

  test('the read time follows the server clock', () async {
    const ahead = 3600000;
    final now = DateTime.now().millisecondsSinceEpoch;
    ServerClock.sync(now + ahead, localNow: now);
    await seed();
    await ReadReceipts.instance.preload(_me, _chatId);
    final before = DateTime.now().millisecondsSinceEpoch + ahead;
    await deliver(_mark(_peer, 3000));
    final after = DateTime.now().millisecondsSinceEpoch + ahead;

    expect(stateOf(2000, mark: 3000).at, inInclusiveRange(before, after));
  });

  group('stampTargetId', () {
    test('picks the last own sent message the peer reached', () {
      final messages = [
        _message('100', 1000),
        _message('200', 2000),
        _message('250', 2500, sender: _peer),
        _message('300', 3000),
      ];

      expect(
        ReadReceipts.stampTargetId(messages, mark: 2600, myId: _me),
        '200',
      );
      expect(
        ReadReceipts.stampTargetId(messages, mark: 3000, myId: _me),
        '300',
      );
      expect(ReadReceipts.stampTargetId(messages, mark: 900, myId: _me), null);
    });

    test('skips deleted, control and unsent messages', () {
      final messages = [
        _message('100', 1000),
        _message('200', 2000, control: true),
        _message('local_1', 2100),
        _message('300', 2200, deleted: true),
      ];

      expect(
        ReadReceipts.stampTargetId(messages, mark: 3000, myId: _me),
        '100',
      );
    });
  });

  test('a reply bound comes from the first later message per sender', () {
    final messages = [
      _message('100', 1000),
      _message('150', 1500, sender: _peer),
      _message('170', 1700, sender: _peer),
      _message('180', 1800, sender: _stranger, control: true),
      _message('200', 2000, sender: _stranger),
    ];

    expect(ReadReceipts.firstMessageTimesAfter(messages, 1000), {
      _peer: 1500,
      _stranger: 2000,
    });
  });

  test('group readers count everyone but me who reached the message', () {
    expect(
      ReadReceipts.readerCount(
        {_me: 9000, _peer: 3000, _stranger: 1000},
        myId: _me,
        messageTime: 2000,
      ),
      1,
    );
  });

  group('ReadBaselines', () {
    test('gives no base outside a session', () {
      final baselines = ReadBaselines();

      expect(baselines.baseFor(_me, _chatId, _peer, knownMarks: [10]), null);
    });

    test('floors an unconfirmed mark at the session start', () {
      final baselines = ReadBaselines()..begin(4000);

      expect(baselines.baseFor(_me, _chatId, _peer, knownMarks: [1000]), 4000);
      expect(baselines.baseFor(_me, _chatId, _peer), 4000);
      expect(baselines.baseFor(_me, _chatId, _peer, knownMarks: [5000]), 5000);
    });

    test('trusts a confirmed mark and forgets it on end', () {
      final baselines = ReadBaselines()
        ..begin(4000)
        ..confirm(_me, _chatId, _peer, 3000)
        ..confirm(_me, _chatId, _peer, 2000);

      expect(baselines.baseFor(_me, _chatId, _peer, knownMarks: [1000]), 3000);

      baselines
        ..end()
        ..begin(4000);

      expect(baselines.baseFor(_me, _chatId, _peer, knownMarks: [1000]), 4000);
    });
  });

  test('the store keeps only the newest receipts of a chat', () async {
    await seed();
    const extra = 5;
    for (var i = 1; i <= AppDatabase.readReceiptsPerChat + extra; i++) {
      await AppDatabase.insertReadReceipt(
        _me,
        _chatId,
        ReadReceipt(userId: _peer, prevMark: i - 1, mark: i, readAt: i),
      );
    }

    final kept = await AppDatabase.loadReadReceipts(_me, _chatId);

    expect(kept, hasLength(AppDatabase.readReceiptsPerChat));
    expect(kept.first.mark, extra + 1);
    expect(kept.last.mark, AppDatabase.readReceiptsPerChat + extra);
  });

  test('a version 29 database gains the receipts table', () async {
    await seed();
    await AppDatabase.close();
    final path = '${directory.path}${Platform.pathSeparator}promax.db';
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('DROP TABLE read_receipts');
    await raw.setVersion(29);
    await raw.close();

    await AppDatabase.insertReadReceipt(
      _me,
      _chatId,
      const ReadReceipt(userId: _peer, prevMark: 0, mark: 3000, readAt: 4000),
    );

    expect(await AppDatabase.loadReadReceipts(_me, _chatId), const [
      ReadReceipt(userId: _peer, prevMark: 0, mark: 3000, readAt: 4000),
    ]);
  });
}
