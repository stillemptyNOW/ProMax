import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/chat_notes_store.dart';
import 'package:promax/core/storage/quick_replies_store.dart';
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

  test('quick replies add, edit, reorder and drop blanks', () async {
    final store = QuickRepliesStore.instance;
    await store.load();
    expect(await store.add('Первый'), isTrue);
    expect(await store.add('Второй'), isTrue);
    expect(await store.add('  Третий '), isTrue);
    expect(await store.add('Первый'), isTrue);
    expect(store.items.value, ['Первый', 'Второй', 'Третий']);

    await store.move(2, 0);
    expect(store.items.value, ['Третий', 'Первый', 'Второй']);

    await store.update(1, 'Изменённый');
    await store.removeAt(2);
    await store.load();
    expect(store.items.value, ['Третий', 'Изменённый']);

    await store.update(0, '');
    expect(store.items.value, ['Изменённый']);
  });

  test('quick replies stop at the limit', () async {
    final store = QuickRepliesStore.instance;
    await store.load();
    for (var i = 0; i < QuickRepliesStore.maxCount; i++) {
      expect(await store.add('Шаблон $i'), isTrue);
    }
    expect(await store.add('Лишний'), isFalse);
    expect(store.items.value.length, QuickRepliesStore.maxCount);
  });
}
