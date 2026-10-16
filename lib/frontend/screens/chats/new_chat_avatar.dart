import 'dart:io';

import '../../../backend/modules/chats.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/logger.dart';
import '../../../main.dart';

Future<bool> setNewChatAvatar(int chatId, File avatar) async {
  try {
    final url = await chats.requestChatPhotoUploadUrl(api);
    if (url == null) return false;
    final bytes = await compressAvatarFile(avatar.path);
    if (bytes == null) return false;
    final token = await fileUploader.uploadImage(
      Uri.parse(url),
      bytes,
      filename: 'avatar.jpg',
    );
    if (token == null) return false;
    return await chats.setChatPhoto(api, chatId: chatId, photoToken: token);
  } catch (e) {
    logger.w('Аватар нового чата $chatId не установлен: $e');
    return false;
  }
}
