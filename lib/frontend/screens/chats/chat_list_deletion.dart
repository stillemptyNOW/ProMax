import '../../../backend/modules/chat_deletion_plan.dart';
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
  required int myId,
}) =>
    kind == ChatListDeleteKind.ownedGroup &&
    ownerDeletesForAll(
      chatId: chat.id,
      chatType: chat.type,
      owner: chat.owner,
      myId: myId,
    );
