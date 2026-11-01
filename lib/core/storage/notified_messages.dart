import 'app_database.dart';

abstract final class NotifiedMessages {
  static const limit = 64;

  static Future<bool> claim(int accountId, int chatId, String messageId) =>
      AppDatabase.claimNotification(accountId, chatId, messageId, limit: limit);
}
