import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/read_receipts.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/read_receipt.dart';
import 'package:promax/core/storage/token_storage.dart';
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
    directory = Directory.systemTemp.createTempSync('synthetic_read_receipts');
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    addTearDown(() async {
      ReadReceipts.instance.resetForTest();
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

  MessageReadState stateOf(int time, {int? mark, int? replyTime}) =>
      ReadReceipts.instance.stateFor(
        accountId: _me,
        chatId: _chatId,
        userId: _peer,
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

  test('a reader unknown to the chat gets no invented time', () async {
    await seed(withPeer: false);
    await deliver(_mark(_stranger, 3000));

    expect(await AppDatabase.loadReadReceipts(_me, _chatId), isEmpty);
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
