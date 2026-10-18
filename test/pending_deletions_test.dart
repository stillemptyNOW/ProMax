import 'dart:async';

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_deletion_plan.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/backend/modules/pending_deletions.dart';
import 'package:promax/backend/modules/server_outcome.dart';
import 'package:promax/frontend/screens/chats/deletion_feedback.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = 7;
const _other = 8;
const _chat = 4242;

CachedMessage _message(String id, {int sender = _me}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: _chat,
  senderId: sender,
  text: 'синтетика $id',
  time: 5000,
);

typedef _Delete = ({int chatId, List<String> ids, bool forEveryone});

class _FakeGateway implements PendingDeletionGateway {
  bool online = true;
  int epoch = 1;
  int? account = _me;
  final StreamController<void> _online = StreamController.broadcast();
  final List<_Delete> deletes = [];
  final List<({int accountId, int chatId, bool forAll, bool historyErased})>
  chatDeletes = [];
  final List<List<String>> forgotten = [];
  ServerOutcome Function(List<String> ids, bool forEveryone) onDelete =
      (_, _) => const ServerDone();
  ServerOutcome chatOutcome = const ServerDone();
  ChatDeletionResult Function(int chatId, bool historyErased)? onChatDelete;

  void goOnline() {
    online = true;
    epoch++;
    _online.add(null);
  }

  @override
  bool get isOnline => online;

  @override
  int get sessionEpoch => epoch;

  @override
  Stream<void> get wentOnline => _online.stream;

  @override
  Future<int?> activeAccountId() async => account;

  @override
  Future<ServerOutcome> deleteMessages(
    int chatId,
    List<String> messageIds, {
    required bool forEveryone,
  }) async {
    deletes.add((chatId: chatId, ids: messageIds, forEveryone: forEveryone));
    return onDelete(messageIds, forEveryone);
  }

  @override
  Future<ChatDeletionResult> deleteChat(
    int accountId,
    int chatId, {
    required bool forAll,
    required bool historyErased,
  }) async {
    chatDeletes.add((
      accountId: accountId,
      chatId: chatId,
      forAll: forAll,
      historyErased: historyErased,
    ));
    return onChatDelete?.call(chatId, historyErased) ??
        ChatDeletionResult(chatOutcome);
  }

  @override
  Future<ServerOutcome> leaveChat(int accountId, int chatId) async =>
      chatOutcome;

  @override
  Future<void> forgetMessages(
    int accountId,
    int chatId,
    List<String> ids,
  ) async => forgotten.add(ids);

  @override
  Future<List<CachedMessage>> loadMessages(
    int accountId,
    int chatId,
    List<String> ids,
  ) async => [for (final id in ids) _message(id)];
}

void main() {
  final pending = PendingDeletions.instance;
  late _FakeGateway gateway;
  late List<RestoredMessages> restored;
  late List<PendingDeletionReport> reports;
  late StreamSubscription<RestoredMessages> restoredSub;
  late StreamSubscription<PendingDeletionReport> reportsSub;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    gateway = _FakeGateway();
    restored = [];
    reports = [];
    restoredSub = pending.restored.listen(restored.add);
    reportsSub = pending.reports.listen(reports.add);
    await pending.start(gateway);
  });

  tearDown(() async {
    await restoredSub.cancel();
    await reportsSub.cancel();
    await pending.stop();
  });

  List<String> holdOwn(List<String> ids, {bool forEveryone = true}) =>
      pending.holdMessages(
        accountId: _me,
        chatId: _chat,
        parts: [
          (
            messages: [for (final id in ids) _message(id)],
            forEveryone: forEveryone,
            fallbackToSelf: false,
          ),
        ],
      );

  test('undo restores the messages and never reaches the server', () async {
    final keys = holdOwn(['11', '12']);
    expect(pending.isMessageHeld(_me, _chat, '11'), isTrue);

    expect(pending.cancel(keys), isTrue);
    await settle();

    expect(pending.isMessageHeld(_me, _chat, '11'), isFalse);
    expect(gateway.deletes, isEmpty);
    expect(restored.single.messages.map((m) => m.id), ['11', '12']);
  });

  test('commit deletes on the server and then locally', () async {
    final keys = holdOwn(['21', '22']);
    pending.commit(keys);
    await settle();

    expect(gateway.deletes.single.ids, ['21', '22']);
    expect(gateway.deletes.single.forEveryone, isTrue);
    expect(gateway.forgotten.single, ['21', '22']);
    expect(pending.isMessageHeld(_me, _chat, '21'), isFalse);
    expect(pending.cancel(keys), isFalse);
    expect(restored, isEmpty);
  });

  test('a deletion for everyone reports what the server confirmed', () async {
    pending.commit(holdOwn(['23', '24']));
    await settle();

    final confirmed = reports.single as PendingDeletionConfirmed;
    expect(confirmed.kind, PendingDeletionKind.messages);
    expect(confirmed.count, 2);
    expect(
      pendingDeletionReportText(
        confirmed,
        lookupAppLocalizations(const Locale('ru')),
      ),
      'Удалено у обоих: 2',
    );
  });

  test('a deletion only for me stays quiet once it went through', () async {
    pending.commit(holdOwn(['25'], forEveryone: false));
    await settle();

    expect(gateway.deletes.single.forEveryone, isFalse);
    expect(reports, isEmpty);
  });

  test(
    'messages the server no longer knows are reported, not hidden',
    () async {
      gateway.onDelete = (_, _) => const ServerRejected('', notFound: true);
      pending.commit(holdOwn(['26']));
      await settle();

      expect(pending.isMessageHeld(_me, _chat, '26'), isFalse);
      expect(gateway.forgotten.single, ['26']);
      expect((reports.single as PendingDeletionAlreadyGone).count, 1);
    },
  );

  test(
    'a commit while offline says the deletion waits for the network',
    () async {
      gateway.online = false;
      pending.commit(holdOwn(['27']));
      await settle();

      expect(gateway.deletes, isEmpty);
      expect(reports.single, isA<PendingDeletionStalled>());

      gateway.goOnline();
      await settle();
      expect(gateway.deletes.single.ids, ['27']);
      expect(reports.last, isA<PendingDeletionConfirmed>());
    },
  );

  test('a server refusal brings the messages back with the reason', () async {
    gateway.onDelete = (_, _) => const ServerRejected('слишком старое');
    pending.commit(holdOwn(['31']));
    await settle();

    expect(pending.isMessageHeld(_me, _chat, '31'), isFalse);
    expect(gateway.forgotten, isEmpty);
    expect(restored.single.messages.single.id, '31');
    final failure = reports.single as PendingDeletionFailed;
    expect(failure.kind, PendingDeletionKind.messages);
    expect(failure.message, 'слишком старое');
  });

  test('offline deletions wait and go out once the session is back', () async {
    gateway.online = false;
    pending.commit(holdOwn(['41']));
    await settle();
    expect(gateway.deletes, isEmpty);
    expect(pending.isMessageHeld(_me, _chat, '41'), isTrue);

    gateway.goOnline();
    await settle();
    expect(gateway.deletes.single.ids, ['41']);
    expect(pending.isMessageHeld(_me, _chat, '41'), isFalse);
  });

  test('a dropped request is retried instead of being lost', () async {
    var calls = 0;
    gateway.onDelete = (_, _) =>
        calls++ == 0 ? const ServerUnreachable('таймаут') : const ServerDone();
    pending.commit(holdOwn(['51']));
    await settle();
    expect(pending.entries.single.attempts, 1);
    expect(restored, isEmpty);

    await pending.flush();
    expect(gateway.deletes.length, 2);
    expect(pending.entries, isEmpty);
  });

  test('pending deletions survive a restart and are committed', () async {
    gateway.online = false;
    holdOwn(['61', '62']);
    await pending.stop();

    final revived = _FakeGateway();
    await pending.start(revived);
    await settle();

    expect(revived.deletes.single.ids, ['61', '62']);
    expect(revived.forgotten.single, ['61', '62']);
    expect(pending.entries, isEmpty);
  });

  test('another account keeps its deletions until it is active', () async {
    gateway.account = _other;
    pending.commit(holdOwn(['71']));
    await settle();
    expect(gateway.deletes, isEmpty);

    gateway.account = _me;
    await pending.flush();
    expect(gateway.deletes.single.ids, ['71']);
  });

  test('closing undo windows commits them for an account switch', () async {
    var closed = 0;
    final sub = pending.undoWindowsClosed.listen((_) => closed++);
    holdOwn(['81']);
    await pending.settleBeforeAccountChange();
    await sub.cancel();

    expect(closed, 1);
    expect(gateway.deletes.single.ids, ['81']);
  });

  test('peer messages the server keeps are deleted only for me', () async {
    gateway.onDelete = (ids, forEveryone) => forEveryone && ids.contains('92')
        ? const ServerRejected('чужое сообщение')
        : const ServerDone();
    final keys = pending.holdMessages(
      accountId: _me,
      chatId: _chat,
      parts: [
        (
          messages: [
            _message('91'),
            _message('92', sender: _other),
          ],
          forEveryone: true,
          fallbackToSelf: true,
        ),
      ],
    );
    pending.commit(keys);
    await settle();

    expect(gateway.deletes.last.ids, ['92']);
    expect(gateway.deletes.last.forEveryone, isFalse);
    expect(
      gateway.deletes.where((d) => d.forEveryone && d.ids.length == 1).length,
      2,
    );
    expect((reports.single as PendingDeletionKeptForPeer).count, 1);
    expect(restored, isEmpty);
  });

  test(
    'a message deleted while sending is removed once it has an id',
    () async {
      pending.cancelSending(_me, _chat, ['temp_1_1']);
      expect(
        pending.claimSent(
          accountId: _me,
          chatId: _chat,
          tempId: 'temp_2_2',
          realId: '100',
        ),
        isFalse,
      );
      expect(
        pending.claimSent(
          accountId: _me,
          chatId: _chat,
          tempId: 'temp_1_1',
          realId: '101',
        ),
        isTrue,
      );
      expect(pending.isMessageHeld(_me, _chat, '101'), isTrue);
      await settle();
      expect(gateway.deletes.single.ids, ['101', 'temp_1_1']);
      expect(gateway.deletes.single.forEveryone, isTrue);
      expect(gateway.forgotten.single, ['101', 'temp_1_1']);
    },
  );

  test('chat removal hides the chat until the server answers', () async {
    gateway.chatOutcome = const ServerRejected('чат не найден', notFound: true);
    final key = pending.holdChat(
      accountId: _me,
      chatId: _chat,
      kind: PendingDeletionKind.deleteChat,
      forAll: true,
    );
    expect(pending.isChatHeld(_chat, accounts: {_me}), isTrue);
    expect(pending.isChatHeld(_chat, accounts: {_other}), isFalse);

    pending.commit([key]);
    await settle();

    expect(gateway.chatDeletes.single.forAll, isTrue);
    expect(pending.isChatHeld(_chat), isFalse);
    final failure = reports.single as PendingDeletionFailed;
    expect(failure.kind, PendingDeletionKind.deleteChat);
  });

  test('a chat removal stuck offline tells the user once', () async {
    gateway.chatOutcome = const ServerUnreachable('таймаут');
    final keys = [
      pending.holdChat(
        accountId: _me,
        chatId: _chat,
        kind: PendingDeletionKind.deleteChat,
        forAll: true,
      ),
    ];
    pending.commit(keys);
    await settle();
    expect(reports, isEmpty);

    await pending.flush();
    await pending.flush();
    await settle();

    expect(pending.isChatHeld(_chat), isTrue);
    expect(gateway.chatDeletes, hasLength(3));
    expect(gateway.chatDeletes.map((d) => d.forAll), everyElement(isTrue));
    final stalled = reports.single as PendingDeletionStalled;
    expect(stalled.kind, PendingDeletionKind.deleteChat);
    expect(
      pendingDeletionReportText(
        stalled,
        lookupAppLocalizations(const Locale('ru')),
      ),
      'Удаление пока не дошло до сервера, ProMax повторит попытку',
    );
  });

  String holdChatForAll([int chatId = _chat]) => pending.holdChat(
    accountId: _me,
    chatId: chatId,
    kind: PendingDeletionKind.deleteChat,
    forAll: true,
  );

  test('many chats stuck offline share a single notice', () async {
    gateway.chatOutcome = const ServerUnreachable('таймаут');
    pending.commit([for (var i = 0; i < 4; i++) holdChatForAll(_chat + i)]);
    await settle();
    await pending.flush();
    await pending.flush();
    await settle();

    expect(gateway.chatDeletes, hasLength(12));
    expect(reports.whereType<PendingDeletionStalled>(), hasLength(1));
  });

  test('a new stall after the queue recovered is reported again', () async {
    gateway.chatOutcome = const ServerUnreachable('таймаут');
    pending.commit([holdChatForAll()]);
    await settle();
    await pending.flush();
    expect(reports.whereType<PendingDeletionStalled>(), hasLength(1));

    gateway.chatOutcome = const ServerDone();
    await pending.flush();
    expect(pending.entries, isEmpty);

    gateway.chatOutcome = const ServerUnreachable('таймаут');
    pending.commit([holdChatForAll(_chat + 1)]);
    await settle();
    await pending.flush();
    expect(reports.whereType<PendingDeletionStalled>(), hasLength(2));
  });

  test('an erased history with a refused removal is told apart', () async {
    gateway.onChatDelete = (_, _) => const ChatDeletionResult(
      ServerRejected('нет доступа'),
      historyErased: true,
    );
    pending.commit([holdChatForAll()]);
    await settle();

    expect(pending.isChatHeld(_chat), isFalse);
    final report = reports.single as PendingDeletionErasedOnly;
    expect(report.message, 'нет доступа');
  });

  test('after the erase went through a retry only removes the chat', () async {
    gateway.onChatDelete = (_, historyErased) => historyErased
        ? const ChatDeletionResult(ServerDone(), historyErased: true)
        : const ChatDeletionResult(
            ServerUnreachable('таймаут'),
            historyErased: true,
          );
    pending.commit([holdChatForAll()]);
    await settle();
    expect(pending.entries.single.historyErased, isTrue);
    final stored =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                PendingDeletions.storageKey,
              )!,
            )
            as List;
    expect((stored.single as Map)['h'], isTrue);

    await pending.flush();
    expect(gateway.chatDeletes.map((d) => d.historyErased), [false, true]);
    expect(pending.entries, isEmpty);
    expect(
      reports.single,
      isA<PendingDeletionConfirmed>().having(
        (r) => r.kind,
        'kind',
        PendingDeletionKind.deleteChat,
      ),
    );
  });

  test('the erased step survives a restart', () async {
    final entry = PendingDeletion.fromJson(
      const PendingDeletion(
        key: 'k',
        accountId: _me,
        chatId: _chat,
        kind: PendingDeletionKind.deleteChat,
        forEveryone: true,
        historyErased: true,
        attempts: 1,
      ).toJson(),
    );
    expect(entry!.historyErased, isTrue);
    expect(entry.retried().historyErased, isTrue);
  });

  test('a chat of unknown type comes back with its own reason', () async {
    gateway.onChatDelete = (_, _) => const ChatDeletionResult.typeUnknown();
    pending.commit([holdChatForAll()]);
    await settle();

    expect(pending.isChatHeld(_chat), isFalse);
    expect(reports.single, isA<PendingDeletionChatTypeUnknown>());
  });
}
