import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/chats/chat/chat_controller.dart';
import 'package:promax/frontend/screens/chats/chat/chat_media_send_controller.dart';
import 'package:promax/frontend/screens/chats/chat/upload_status.dart';

void main() {
  test(
    'blocks attachments if group protection starts during confirmation',
    () async {
      final chat = ChatController()
        ..myId = 101
        ..chatId = 202;
      final panel = ValueNotifier(false);
      final status = ValueNotifier(const UploadStatus());
      var allowed = true;
      var sent = false;
      final media = ChatMediaSendController(
        chatController: chat,
        showAttachmentPanel: panel,
        uploadStatus: status,
        bumpMessages: () {},
        scrollToBottom: () {},
        setLastSentId: (_) {},
        notify: (_) {},
        isMounted: () => true,
        encryptionEnabled: () => false,
        encryptOutgoing: (text, {notify = true}) async => text,
        confirmSend: () async {
          allowed = false;
          return true;
        },
        allowAttachment: () async => allowed,
        markHasScheduled: () {},
      );
      addTearDown(() {
        media.dispose();
        chat.dispose();
        panel.dispose();
        status.dispose();
      });
      await media.sendAttachMessage([], () async {
        sent = true;
        return null;
      });
      expect(sent, isFalse);
      expect(chat.messages, isEmpty);
    },
  );
}
