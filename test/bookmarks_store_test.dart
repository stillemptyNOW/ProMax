import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/bookmarks_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BookmarksStore.instance.load();
  });

  test('toggling adds newest first and removes again', () async {
    final store = BookmarksStore.instance;
    expect(
      await store.toggle(
        chatId: 5,
        messageId: '10',
        chatName: 'Синтетика',
        text: 'первое',
        time: 1,
      ),
      isTrue,
    );
    await store.toggle(
      chatId: 6,
      messageId: '11',
      chatName: 'Синтетика 2',
      text: 'второе',
      time: 2,
    );
    expect(store.items.value.first.messageId, '11');
    expect(store.contains(5, '10'), isTrue);
    expect(
      await store.toggle(
        chatId: 5,
        messageId: '10',
        chatName: 'Синтетика',
        text: 'первое',
        time: 1,
      ),
      isFalse,
    );
    expect(store.contains(5, '10'), isFalse);
  });

  test('bookmarks survive a reload', () async {
    final store = BookmarksStore.instance;
    await store.toggle(
      chatId: -7,
      messageId: '20',
      chatName: 'Группа',
      text: 'x' * 3000,
      time: 3,
    );
    store.items.value = const [];
    await store.load();
    expect(store.items.value.single.chatId, -7);
    expect(store.items.value.single.text.length, BookmarksStore.maxTextLength);
  });
}
