import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_deletion_plan.dart';
import 'package:promax/backend/modules/server_outcome.dart';

const _me = 41;
const _other = 42;
const _chat = 7301;

ChatDeletionPlan? _plan(
  String? type, {
  bool forAll = true,
  int chatId = _chat,
  int? owner,
}) => ChatDeletionPlan.of(
  forAll: forAll,
  chatId: chatId,
  chatType: type,
  owner: owner,
  myId: _me,
);

void main() {
  group('who may delete a chat for everyone', () {
    test('a dialog is only ever deleted for me', () {
      final plan = _plan('DIALOG');

      expect(plan, ChatDeletionPlan.forMe);
      expect(plan!.payload(chatId: _chat, lastEventTime: 5000), {
        'chatId': _chat,
        'lastEventTime': 5000,
        'forAll': false,
      });
    });

    test('saved messages are never deleted for anyone else', () {
      expect(_plan('DIALOG', chatId: 0), ChatDeletionPlan.forMe);
    });

    test('only the owner deletes a group for its members', () {
      expect(_plan('CHAT', owner: _me), ChatDeletionPlan.forEveryone);
      expect(_plan('CHAT', owner: _other), ChatDeletionPlan.forMe);
      expect(_plan('CHAT'), ChatDeletionPlan.forMe);
    });

    test('a channel never goes out with forAll, even for its owner', () {
      expect(_plan('CHANNEL', owner: _me), ChatDeletionPlan.forMe);
      expect(
        ownerDeletesForAll(
          chatId: _chat,
          chatType: 'CHANNEL',
          owner: _me,
          myId: _me,
        ),
        isFalse,
      );
    });

    test('an unknown type is refused instead of guessed', () {
      expect(_plan(null), isNull);
      expect(_plan(null, forAll: false), ChatDeletionPlan.forMe);
    });

    test('deleting only for me never asks for anything else', () {
      for (final type in ['DIALOG', 'CHAT', 'CHANNEL']) {
        final plan = _plan(type, forAll: false, owner: _me)!;
        expect(plan.forAll, isFalse);
        expect(
          plan.payload(chatId: _chat, lastEventTime: 1)['forAll'],
          isFalse,
        );
      }
    });
  });

  test('a local refusal keeps its reason through the outcome', () {
    final refused = ChatDeletionResult.refused(
      ChatDeletionRefusal.eventTimeUnknown,
    );

    expect(refused.ok, isFalse);
    expect(refused.forAll, isFalse);
    expect(refused.refusal, ChatDeletionRefusal.eventTimeUnknown);
    expect(
      ChatDeletionRefusal.of(const ServerRejected('отказ сервера')),
      isNull,
    );
  });
}
