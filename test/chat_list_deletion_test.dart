import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/frontend/screens/chats/chat_list_deletion.dart';

const _me = 31;
const _peer = 32;

CachedChat _chat(
  String type, {
  int id = 7001,
  int? owner,
  Set<int>? admins,
  Set<String> options = const {},
}) => CachedChat(
  id: id,
  accountId: _me,
  type: type,
  unreadCount: 0,
  lastEventTime: 0,
  cachedAt: 0,
  dontDisturbUntil: 0,
  isOnline: false,
  seenTime: 0,
  participants: const {_me: 0, _peer: 0},
  options: options,
  owner: owner,
  admins: admins ?? const {},
);

bool _forAll(
  CachedChat chat, {
  bool erasePeerChosen = true,
  bool? deleteForAll = true,
}) => chatListDeletesForAll(
  chatListDeleteKind(chat, _me),
  chat,
  myId: _me,
  deleteForAll: deleteForAll,
  erasePeerChosen: erasePeerChosen,
);

void main() {
  group('what the chat list may delete', () {
    test('a dialog is deleted for both only when chosen', () {
      final dialog = _chat('DIALOG');

      expect(chatListDeleteKind(dialog, _me), ChatListDeleteKind.personal);
      expect(_forAll(dialog), isTrue);
      expect(_forAll(dialog, erasePeerChosen: false), isFalse);
    });

    test('a dialog stays for the peer when the server forbids it', () {
      final dialog = _chat('DIALOG');

      expect(_forAll(dialog, deleteForAll: false), isFalse);
      expect(
        chatListAllowsForAll(dialog, myId: _me, deleteForAll: false),
        isFalse,
      );
    });

    test('a bot dialog is never deleted for the bot', () {
      final bot = _chat('DIALOG', options: {'BOT'});

      expect(chatListAllowsForAll(bot, myId: _me, deleteForAll: true), isFalse);
      expect(_forAll(bot), isFalse);
    });

    test('saved messages are never deleted for anyone else', () {
      expect(_forAll(_chat('DIALOG', id: 0)), isFalse);
    });

    test('the owner deletes a group for its members, not a channel', () {
      final group = _chat('CHAT', owner: _me);
      final channel = _chat('CHANNEL', owner: _me);

      expect(chatListDeleteKind(group, _me), ChatListDeleteKind.ownedGroup);
      expect(chatListDeleteKind(channel, _me), ChatListDeleteKind.ownedGroup);
      expect(_forAll(group, erasePeerChosen: false), isTrue);
      expect(_forAll(channel, erasePeerChosen: false), isFalse);
    });

    test('an admin who is not the owner cannot delete for members', () {
      final group = _chat('CHAT', owner: _peer, admins: {_me});

      expect(chatListDeleteKind(group, _me), ChatListDeleteKind.unavailable);
      expect(_forAll(group), isFalse);
    });
  });
}
