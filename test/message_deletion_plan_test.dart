import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/deletion_policy.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/frontend/screens/chats/chat/message_deletion.dart';
import 'package:promax/l10n/app_localizations.dart';

const _me = 3;
const _peer = 4;
const _now = 10 * 86400 * 1000;
const _day = Duration(days: 1);

CachedMessage _message(
  String id,
  int sender, {
  Duration age = const Duration(minutes: 5),
  Map<String, dynamic>? payload,
}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: 55,
  senderId: sender,
  text: 'синтетика $id',
  time: _now - age.inMilliseconds,
  payload: payload,
);

MessageDeletionRules _rules(
  MessageDeletionChat chat, {
  bool canDeleteAny = false,
  bool canDeleteOwn = false,
  Duration editTimeout = _day,
}) => MessageDeletionRules(
  chat: chat,
  myId: _me,
  nowMs: _now,
  editTimeout: editTimeout,
  canDeleteAny: canDeleteAny,
  canDeleteOwn: canDeleteOwn,
);

MessageDeletionPlan _plan(
  List<CachedMessage> messages, [
  MessageDeletionChat chat = MessageDeletionChat.dialog,
  bool canDeleteAny = false,
]) => MessageDeletionPlan(
  messages: messages,
  rules: _rules(chat, canDeleteAny: canDeleteAny),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('ru'));

  group('a dialog', () {
    test('offers "for everyone" for fresh own messages', () {
      final plan = _plan([_message('1', _me), _message('2', _me)]);

      expect(plan.offersForEveryone, isTrue);
      expect(plan.notes(l10n), isEmpty);
      final part = plan.parts(forEveryone: true).single;
      expect(part.forEveryone, isTrue);
      expect(part.messages.map((m) => m.id), ['1', '2']);
    });

    test('a peer message turns the whole selection into "for me"', () {
      final plan = _plan([_message('1', _me), _message('2', _peer)]);

      expect(plan.offersForEveryone, isFalse);
      expect(plan.parts(forEveryone: true).single.forEveryone, isFalse);
      expect(plan.notes(l10n), [
        l10n.deleteMessagesPeerOnlyForMe,
        l10n.deleteMessagesSelectionOnlyForMe,
      ]);
    });

    test('an own message older than edit-timeout is not offered', () {
      final plan = _plan([
        _message('1', _me),
        _message('2', _me, age: const Duration(hours: 25)),
      ]);

      expect(plan.offersForEveryone, isFalse);
      expect(
        plan.notes(l10n).first,
        'Удалить у собеседника можно только свои сообщения не старше '
        '24 часов — это ограничение сервера MAX',
      );
    });

    test('the age limit follows the server value and server time', () {
      final rules = _rules(
        MessageDeletionChat.dialog,
        editTimeout: const Duration(days: 7),
      );

      expect(
        rules.allowsForEveryone(
          _message('1', _me, age: const Duration(days: 6)),
        ),
        isTrue,
      );
      expect(
        rules.denialFor(_message('2', _me, age: const Duration(days: 7))),
        ForEveryoneDenial.tooOld,
      );
    });

    test('unsent and scheduled messages are never offered', () {
      final rules = _rules(MessageDeletionChat.dialog);

      expect(
        rules.denialFor(_message('temp_1_1', _me)),
        ForEveryoneDenial.notSent,
      );
      expect(
        rules.denialFor(
          _message(
            '9',
            _me,
            payload: {
              'delayedAttributes': {'timeToFire': _now + 60000},
            },
          ),
        ),
        ForEveryoneDenial.scheduled,
      );
    });

    test('"for me" keeps everything local', () {
      final plan = _plan([_message('1', _me)]);

      expect(plan.parts(forEveryone: false).single.forEveryone, isFalse);
    });
  });

  group('groups and channels', () {
    test('an admin with delete rights deletes any message without a limit', () {
      final plan = _plan(
        [
          _message('1', _peer, age: const Duration(days: 30)),
          _message('2', _me, age: const Duration(days: 30)),
        ],
        MessageDeletionChat.group,
        true,
      );

      expect(plan.offersForEveryone, isTrue);
    });

    test('a member deletes only fresh own messages for everyone', () {
      expect(
        _plan([
          _message('1', _me),
        ], MessageDeletionChat.group).offersForEveryone,
        isTrue,
      );
      final mixed = _plan([
        _message('1', _me),
        _message('2', _peer),
      ], MessageDeletionChat.group);
      expect(mixed.offersForEveryone, isFalse);
      expect(mixed.notes(l10n).first, l10n.deleteMessagesOthersOnlyForMe);
    });

    test('a channel goes by rights, not by age', () {
      final old = _message('1', _me, age: const Duration(days: 30));
      final foreign = _message('2', _peer, age: const Duration(days: 30));

      expect(
        _rules(
          MessageDeletionChat.channel,
          canDeleteOwn: true,
        ).allowsForEveryone(old),
        isTrue,
      );
      expect(
        _rules(
          MessageDeletionChat.channel,
          canDeleteOwn: true,
        ).allowsForEveryone(foreign),
        isFalse,
      );
      expect(
        _rules(
          MessageDeletionChat.channel,
          canDeleteAny: true,
        ).allowsForEveryone(foreign),
        isTrue,
      );
      expect(
        _rules(MessageDeletionChat.channel).allowsForEveryone(old),
        isFalse,
      );
    });
  });

  test('age limits read naturally in Russian', () {
    expect(deletionAgeLimitText(l10n, const Duration(days: 1)), '24 часов');
    expect(deletionAgeLimitText(l10n, const Duration(days: 7)), '7 дней');
    expect(deletionAgeLimitText(l10n, const Duration(days: 21)), '21 дня');
    expect(deletionAgeLimitText(l10n, const Duration(hours: 1)), '1 часа');
    expect(deletionAgeLimitText(l10n, const Duration(minutes: 90)), '90 минут');
  });
}
