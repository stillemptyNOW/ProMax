import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/bot_callback_answers.dart';

void main() {
  late BotCallbackAnswers answers;
  late List<String> unclaimed;

  setUp(() {
    answers = BotCallbackAnswers();
    unclaimed = [];
    answers.unclaimed.listen(unclaimed.add);
  });

  test('an answer goes to the button that asked for it', () async {
    final shown = <String>[];
    answers.anchor('501', 'cb-1', (text) {
      shown.add(text);
      return true;
    });

    answers.deliver({
      'messageId': 501,
      'callbackId': 'cb-1',
      'notification': 'Синтетический ответ',
    });
    await pumpEventQueue();

    expect(shown, ['Синтетический ответ']);
    expect(unclaimed, isEmpty);
  });

  test('without a live button the answer becomes a notification', () async {
    final release = answers.anchor('502', 'cb-2', (_) => false);
    answers.deliver({'callbackId': 'cb-2', 'text': 'Синтетика'});
    release();
    answers.deliver({'callbackId': 'cb-3', 'text': 'Другая синтетика'});
    await pumpEventQueue();

    expect(unclaimed, ['Синтетика', 'Другая синтетика']);
  });

  test('the same text shown from the reply is not repeated', () async {
    answers.noteShown('503', 'cb-4', 'Повтор');
    answers.deliver({
      'messageId': '503',
      'callbackId': 'cb-4',
      'text': 'Повтор',
    });
    answers.deliver({'payload': 'нет текста'});
    await pumpEventQueue();

    expect(unclaimed, isEmpty);
  });
}
