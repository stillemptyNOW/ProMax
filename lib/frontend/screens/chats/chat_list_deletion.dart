import '../../../backend/modules/chats.dart' show CachedChat;

enum ChatListDeleteKind { personal, ownedGroup, unavailable }

ChatListDeleteKind chatListDeleteKind(CachedChat chat, int myId) {
  if (chat.type == 'DIALOG') return ChatListDeleteKind.personal;
  if (chat.owner == myId) return ChatListDeleteKind.ownedGroup;
  return ChatListDeleteKind.unavailable;
}

bool chatListDeletesForAll(
  ChatListDeleteKind kind,
  CachedChat chat, {
  required bool erasePeerChosen,
}) => switch (kind) {
  ChatListDeleteKind.personal => erasePeerChosen && chat.id != 0,
  ChatListDeleteKind.ownedGroup => true,
  ChatListDeleteKind.unavailable => false,
};
