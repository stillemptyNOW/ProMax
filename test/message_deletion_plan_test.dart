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

void main() {
  final l10n = lookupAppLocalizations(const Locale('ru'));
  final mixed = [_message('1', _me), _message('2', _peer), _message('3', _me)];

  test('a dialog keeps own messages for both and tries the peer ones', () {
    final plan = MessageDeletionPlan(
      myId: _me,
      messages: mixed,
      isDialog: true,
      canDeleteOthersForEveryone: false,
    );
    expect(plan.offersForEveryone, isTrue);
    expect(plan.note(l10n), l10n.deleteMessagesPeerFallbackNote);

    final parts = plan.parts(forEveryone: true);
    expect(parts.first.messages.map((m) => m.id), ['1', '3']);
    expect(parts.first.forEveryone, isTrue);
    expect(parts.first.fallbackToSelf, isFalse);
    expect(parts.last.messages.map((m) => m.id), ['2']);
    expect(parts.last.forEveryone, isTrue);
    expect(parts.last.fallbackToSelf, isTrue);
  });

  test('a peer message no longer drags own messages down to "for me"', () {
    final plan = MessageDeletionPlan(
      myId: _me,
      messages: mixed,
      isDialog: false,
      canDeleteOthersForEveryone: false,
    );
    expect(plan.offersForEveryone, isTrue);
    expect(plan.note(l10n), l10n.deleteMessagesOthersOnlyForMe(1));

    final parts = plan.parts(forEveryone: true);
    expect(parts.first.forEveryone, isTrue);
    expect(parts.last.forEveryone, isFalse);
    expect(parts.last.fallbackToSelf, isFalse);
  });

  test('without rights only foreign messages offer no choice', () {
    final plan = MessageDeletionPlan(
      myId: _me,
      messages: [_message('2', _peer)],
      isDialog: false,
      canDeleteOthersForEveryone: false,
    );
    expect(plan.offersForEveryone, isFalse);
    expect(plan.note(l10n), isNull);
  });

  test('"for me" keeps every part local', () {
    final plan = MessageDeletionPlan(
      myId: _me,
      messages: mixed,
      isDialog: true,
      canDeleteOthersForEveryone: false,
    );
    expect(plan.parts(forEveryone: false).every((p) => !p.forEveryone), isTrue);
  });
}
