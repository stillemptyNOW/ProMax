import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/frontend/screens/chats/chat_list_deletion.dart';

const _me = 31;
const _peer = 32;

CachedChat _chat(String type, {int id = 7001, int? owner, Set<int>? admins}) =>
    CachedChat(
      id: id,
      accountId: _me,
      type: type,
      unreadCount: 0,
      lastEventTime: 0,
      cachedAt: 0,
      dontDisturbUntil: 0,
      isOnline: false,
      seenTime: 0,
      participants: const {},
      owner: owner,
      admins: admins ?? const {},
    );

void main() {
  group('what the chat list may delete', () {
    test('a dialog offers erasing it for the other person', () {
      final dialog = _chat('DIALOG');
      final kind = chatListDeleteKind(dialog, _me);

      expect(kind, ChatListDeleteKind.personal);
      expect(
        chatListDeletesForAll(kind, dialog, erasePeerChosen: true),
        isTrue,
      );
      expect(
        chatListDeletesForAll(kind, dialog, erasePeerChosen: false),
        isFalse,
      );
    });

    test('saved messages are never deleted for anyone else', () {
      final saved = _chat('DIALOG', id: 0);

      expect(
        chatListDeletesForAll(
          chatListDeleteKind(saved, _me),
          saved,
          erasePeerChosen: true,
        ),
        isFalse,
      );
    });

    test('only the owner deletes a group for its members', () {
      for (final type in ['CHAT', 'CHANNEL']) {
        final owned = _chat(type, owner: _me);
        final kind = chatListDeleteKind(owned, _me);

        expect(kind, ChatListDeleteKind.ownedGroup);
        expect(
          chatListDeletesForAll(kind, owned, erasePeerChosen: false),
          isTrue,
        );
      }
    });

    test('an admin who is not the owner cannot delete for members', () {
      final group = _chat('CHAT', owner: _peer, admins: {_me});

      expect(chatListDeleteKind(group, _me), ChatListDeleteKind.unavailable);
      expect(
        chatListDeletesForAll(
          ChatListDeleteKind.unavailable,
          group,
          erasePeerChosen: true,
        ),
        isFalse,
      );
    });
  });
}
