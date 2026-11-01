import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/quick_replies_store.dart';
import 'package:promax/frontend/screens/chats/chat/quick_reply_panel_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _account = 101;
const int _otherAccount = 202;

List<String> _texts(int accountId) => [
  for (final reply in QuickRepliesStore.instance.repliesFor(accountId))
    reply.text,
];

void main() {
  final store = QuickRepliesStore.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store.resetForTest();
  });

  group('QuickRepliesStore', () {
    test('adds, edits, reorders and removes templates', () async {
      await store.load(_account);
      expect(
        await store.add(
          _account,
          title: ' Перезвоню ',
          text: 'Перезвоню позже 📞',
        ),
        QuickReplySaveResult.saved,
      );
      expect(
        await store.add(_account, text: '  **Жирный** и _курсив_  '),
        QuickReplySaveResult.saved,
      );
      expect(
        await store.add(_account, text: 'Третий'),
        QuickReplySaveResult.saved,
      );
      expect(
        await store.add(_account, text: '   '),
        QuickReplySaveResult.empty,
      );

      final first = store.repliesFor(_account).first;
      expect(first.title, 'Перезвоню');
      expect(first.label, 'Перезвоню');
      expect(_texts(_account), [
        'Перезвоню позже 📞',
        '**Жирный** и _курсив_',
        'Третий',
      ]);
      expect(store.repliesFor(_account)[1].label, '**Жирный** и _курсив_');

      await store.move(_account, 2, 0);
      expect(_texts(_account).first, 'Третий');

      final third = store.repliesFor(_account).first;
      await store.update(
        _account,
        third.id,
        title: 'Новое',
        text: 'Изменённый',
      );
      await store.remove(_account, first.id);

      store.resetForTest();
      await store.load(_account);
      final reloaded = store.repliesFor(_account);
      expect(reloaded.map((reply) => reply.text), [
        'Изменённый',
        '**Жирный** и _курсив_',
      ]);
      expect(reloaded.first.title, 'Новое');
      expect(reloaded.first.id, third.id);
    });

    test('keeps templates separate per account', () async {
      await store.add(_account, text: 'Первый аккаунт');
      await store.add(_otherAccount, text: 'Второй аккаунт');
      store.resetForTest();
      await store.ensureLoaded(_account);
      await store.ensureLoaded(_otherAccount);
      expect(_texts(_account), ['Первый аккаунт']);
      expect(_texts(_otherAccount), ['Второй аккаунт']);

      await store.forget(_otherAccount);
      store.resetForTest();
      await store.ensureLoaded(_otherAccount);
      expect(_texts(_otherAccount), isEmpty);
      await store.ensureLoaded(_account);
      expect(_texts(_account), ['Первый аккаунт']);
    });

    test('ignores writes for the unknown account 0', () async {
      expect(await store.add(0, text: 'Никуда'), QuickReplySaveResult.empty);
      expect(store.repliesFor(0), isEmpty);
    });

    test('moves the old global list into the first loaded account', () async {
      SharedPreferences.setMockInitialValues({
        QuickRepliesStore.legacyPrefKey: ['Старый шаблон', '  ', 'Ещё один'],
      });
      await store.load(_account);
      expect(_texts(_account), ['Старый шаблон', 'Ещё один']);
      expect(store.repliesFor(_account).every((r) => r.title.isEmpty), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(QuickRepliesStore.legacyPrefKey), isNull);

      await store.load(_otherAccount);
      expect(_texts(_otherAccount), isEmpty);
    });

    test('drops corrupt entries and survives broken json', () async {
      SharedPreferences.setMockInitialValues({
        QuickRepliesStore.prefKeyFor(_account):
            '[{"id":"a","text":"Хороший"},{"id":"a","text":"Дубль"},'
            '{"text":"Без id"},{"id":"b","text":"  "},42]',
        QuickRepliesStore.prefKeyFor(_otherAccount): '{not json',
      });
      await store.load(_account);
      await store.load(_otherAccount);
      expect(_texts(_account), ['Хороший']);
      expect(_texts(_otherAccount), isEmpty);
    });

    test('stops at the limit', () async {
      for (var i = 0; i < QuickRepliesStore.maxCount; i++) {
        expect(
          await store.add(_account, text: 'Шаблон $i'),
          QuickReplySaveResult.saved,
        );
      }
      expect(
        await store.add(_account, text: 'Лишний'),
        QuickReplySaveResult.limitReached,
      );
      expect(store.repliesFor(_account).length, QuickRepliesStore.maxCount);
    });

    test('matches by title or text and ranks word starts first', () {
      const replies = [
        QuickReply(id: '1', title: '', text: 'Скоро буду дома'),
        QuickReply(id: '2', title: 'Домой', text: 'Еду'),
        QuickReply(id: '3', title: 'Адрес', text: 'Улица Синтетическая, 1'),
      ];
      expect(matchQuickReplies(replies, ''), replies);
      expect(matchQuickReplies(replies, 'дом').map((r) => r.id), ['2', '1']);
      expect(matchQuickReplies(replies, 'синт').map((r) => r.id), ['3']);
      expect(matchQuickReplies(replies, 'нет такого'), isEmpty);
    });
  });

  group('quickReplyQueryAt', () {
    QuickReplyQuery? at(String text, [int? cursor]) =>
        quickReplyQueryAt(text, cursor ?? text.length);

    test('opens on the trigger at the start of the text or a word', () {
      expect(at(';'), const QuickReplyQuery(start: 0, end: 1, text: ''));
      expect(
        at(';пере'),
        const QuickReplyQuery(start: 0, end: 5, text: 'пере'),
      );
      expect(
        at('Привет ;адр'),
        const QuickReplyQuery(start: 7, end: 11, text: 'адр'),
      );
      expect(
        at('строка\n;x1'),
        const QuickReplyQuery(start: 7, end: 10, text: 'x1'),
      );
    });

    test('stays closed inside words, after spaces and for emoticons', () {
      expect(at('a;b'), isNull);
      expect(at('; '), isNull);
      expect(at(';пере звоню'), isNull);
      expect(at(';)'), isNull);
      expect(at(';;'), isNull);
      expect(at('ничего'), isNull);
      expect(at(''), isNull);
      expect(at(';${'я' * 33}'), isNull);
    });

    test('does not clash with slash commands or mentions', () {
      expect(at('/start'), isNull);
      expect(at('/shrug ;'), isNotNull);
      expect(at('@имя'), isNull);
    });

    test('needs the cursor at the end of the token', () {
      expect(at(';abc', 2), isNull);
      expect(
        at(';ab cd', 3),
        const QuickReplyQuery(start: 0, end: 3, text: 'ab'),
      );
    });
  });

  group('insertQuickReplyText', () {
    test('replaces the typed trigger with the template', () {
      const value = TextEditingValue(
        text: 'Ок ;пер',
        selection: TextSelection.collapsed(offset: 7),
      );
      final next = insertQuickReplyText(
        value,
        'Перезвоню 📞',
        replacing: quickReplyQueryAt(value.text, 7),
      );
      expect(next.text, 'Ок Перезвоню 📞');
      expect(next.selection, const TextSelection.collapsed(offset: 15));
    });

    test('inserts at the cursor or over the selection', () {
      const caret = TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(insertQuickReplyText(caret, 'X').text, 'aXb');

      const selected = TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      final replaced = insertQuickReplyText(selected, 'X');
      expect(replaced.text, 'aXd');
      expect(replaced.selection.baseOffset, 2);

      const unfocused = TextEditingValue(text: 'ab');
      expect(insertQuickReplyText(unfocused, 'X').text, 'abX');
    });
  });
}
