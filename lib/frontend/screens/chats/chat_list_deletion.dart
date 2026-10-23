import '../../../backend/modules/chats.dart' show CachedChat;
import '../../../backend/modules/deletion_policy.dart';

enum ChatListDeleteKind { personal, ownedGroup, unavailable }

ChatListDeleteKind chatListDeleteKind(CachedChat chat, int myId) {
  if (chat.type == 'DIALOG') return ChatListDeleteKind.personal;
  if (chat.owner == myId) return ChatListDeleteKind.ownedGroup;
  return ChatListDeleteKind.unavailable;
}

bool chatListAllowsForAll(
  CachedChat chat, {
  required int myId,
  required bool? deleteForAll,
}) => chatForAllAllowed(
  chatId: chat.id,
  chatType: chat.type,
  owner: chat.owner,
  myId: myId,
  peerIsBot:
      chat.type == 'DIALOG' &&
      knownBot(
        dialogPeerId(
          chatId: chat.id,
          myId: myId,
          participants: chat.participants.keys,
        ),
        chatOptions: chat.options,
      ),
  deleteForAll: deleteForAll,
);

bool chatListDeletesForAll(
  ChatListDeleteKind kind,
  CachedChat chat, {
  required int myId,
  required bool? deleteForAll,
  required bool erasePeerChosen,
}) {
  final allowed = chatListAllowsForAll(
    chat,
    myId: myId,
    deleteForAll: deleteForAll,
  );
  return switch (kind) {
    ChatListDeleteKind.personal => erasePeerChosen && allowed,
    ChatListDeleteKind.ownedGroup => allowed,
    ChatListDeleteKind.unavailable => false,
  };
}
