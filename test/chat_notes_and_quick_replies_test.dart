import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/chat_notes_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('chat notes persist per chat and clear when emptied', () async {
    final store = ChatNotesStore.instance;
    await store.load();
    await store.save(-7, '  Синтетическая заметка  ');
    await store.save(9, 'Другая');
    await store.load();
    expect(store.noteFor(-7), 'Синтетическая заметка');
    expect(store.noteFor(9), 'Другая');

    await store.save(-7, '   ');
    await store.load();
    expect(store.noteFor(-7), isNull);
    expect(store.noteFor(9), 'Другая');
  });
}
