import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/frontend/screens/chats/chat/message_deletion.dart';
import 'package:promax/l10n/app_localizations.dart';

const _me = 3;
const _peer = 4;

CachedMessage _message(String id, int sender) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: 55,
  senderId: sender,
  text: 'синтетика $id',
  time: 1000,
);

MessageDeletionPlan _plan(
  List<CachedMessage> messages, {
  bool canDeleteAny = false,
  bool canDeleteOwnPosts = false,
}) => MessageDeletionPlan(
  messages: messages,
  moderation: MessageModeration(
    myId: _me,
    canDeleteAny: canDeleteAny,
    canDeleteOwnPosts: canDeleteOwnPosts,
  ),
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('ru'));

  group('without moderation rights', () {
    test('own and foreign messages are deleted only for me', () {
      final plan = _plan([_message('1', _me), _message('2', _peer)]);

      expect(plan.offersForMembers, isFalse);
      expect(plan.notes(l10n), isEmpty);
      final part = plan.parts(forMembers: true).single;
      expect(part.forEveryone, isFalse);
      expect(part.messages.map((m) => m.id), ['1', '2']);
    });
  });

  group('moderation in groups and channels', () {
    test('an admin with delete rights may remove any message for members', () {
      final plan = _plan([
        _message('1', _peer),
        _message('2', _me),
      ], canDeleteAny: true);

      expect(plan.offersForMembers, isTrue);
      expect(plan.parts(forMembers: true).single.forEveryone, isTrue);
      expect(plan.parts(forMembers: false).single.forEveryone, isFalse);
    });

    test('a post author removes only own posts for subscribers', () {
      final own = _plan([_message('1', _me)], canDeleteOwnPosts: true);
      final mixed = _plan([
        _message('1', _me),
        _message('2', _peer),
      ], canDeleteOwnPosts: true);

      expect(own.offersForMembers, isTrue);
      expect(mixed.offersForMembers, isFalse);
      expect(mixed.notes(l10n), [l10n.deleteMessagesSelectionOnlyForMe]);
    });

    test('unsent messages are never removed for members', () {
      final plan = _plan([_message('temp_1_1', _me)], canDeleteAny: true);

      expect(plan.offersForMembers, isFalse);
    });
  });
}
