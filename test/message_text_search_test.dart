import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/storage/app_database.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

CachedMessage _m(String id, int chat, String text, {bool deleted = false}) =>
    CachedMessage(
      id: id,
      accountId: 1,
      chatId: chat,
      senderId: 2,
      text: text,
      time: int.parse(id),
      deleted: deleted,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('promax_text_search');
    PathProviderPlatform.instance = _Paths(dir.path);
    addTearDown(() async {
      await AppDatabase.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await AppDatabase.init();
    await AppDatabase.saveProfile(
      ProfileData(
        id: 1,
        firstName: 'Синтетика',
        phone: 100000,
        country: 'ZZ',
        accountStatus: 0,
        updateTime: 1,
      ),
    );
    for (final chat in [5, 6, 7]) {
      await chats.cacheServerChat({
        'id': chat,
        'type': 'CHAT',
        'status': 'ACTIVE',
        'title': 'Синтетический чат $chat',
        'participants': {'1': 0, '2': 0},
      }, 1);
    }
    await AppDatabase.saveMessages([
      _m('101', 5, 'Синтетика завтра в школе').toDbRow(),
      _m('102', 6, 'про синтетику ничего').toDbRow(),
      _m('103', 6, 'СИНТЕТИКА громко').toDbRow(),
      _m('104', 7, 'синтетика удалена', deleted: true).toDbRow(),
      _m('105', 7, 'совсем другое').toDbRow(),
    ]);
  });

  test('finds cyrillic text in any case and skips deleted messages', () async {
    final rows = await AppDatabase.searchMessagesText(1, 'синтетик');
    expect(rows.map((r) => r['id']).toSet(), {'101', '102', '103'});
    expect(rows.first['id'], '103');
    expect(await AppDatabase.searchMessagesText(1, '   '), isEmpty);
    expect(await AppDatabase.searchMessagesText(2, 'синтетик'), isEmpty);
  });
}
