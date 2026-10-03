import 'dart:convert';
import 'app_database.dart';

int localUnreadCount({
  required int serverUnread,
  required int locallyRead,
  required int localMark,
  required int lastMessageTime,
}) {
  if (lastMessageTime > 0 && lastMessageTime <= localMark) return 0;
  return (serverUnread - locallyRead).clamp(
    0,
    serverUnread < 0 ? 0 : serverUnread,
  );
}

class LocalReadState {
  final int mark;
  final int serverMark;

  const LocalReadState({this.mark = 0, this.serverMark = 0});

  static String _key(int chatId) => 'promax_local_read_$chatId';

  static Future<LocalReadState> load(int accountId, int chatId) async {
    final raw = await AppDatabase.getSyncValue(accountId, _key(chatId));
    if (raw == null) return const LocalReadState();
    try {
      final decoded = jsonDecode(raw) as Map;
      return LocalReadState(
        mark: (decoded['mark'] as int?) ?? 0,
        serverMark: (decoded['serverMark'] as int?) ?? 0,
      );
    } catch (_) {
      return const LocalReadState();
    }
  }

  Future<void> save(int accountId, int chatId) => AppDatabase.setSyncValue(
    accountId,
    _key(chatId),
    jsonEncode({'mark': mark, 'serverMark': serverMark}),
  );

  static Future<void> record(
    int accountId,
    int chatId,
    int mark, {
    int serverMark = 0,
  }) async {
    final current = await load(accountId, chatId);
    if (mark <= current.mark) return;
    await LocalReadState(
      mark: mark,
      serverMark: current.mark == 0 ? serverMark : current.serverMark,
    ).save(accountId, chatId);
  }
}
