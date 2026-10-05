import '../../backend/modules/messages.dart';
import '../../models/attachment.dart';

class ChatStats {
  ChatStats._({
    required this.total,
    required this.bySender,
    required this.byHour,
    required this.byWeekday,
    required this.media,
    required this.topWords,
    required this.words,
    required this.first,
    required this.last,
    required this.busiestDay,
    required this.busiestDayCount,
  });

  final int total;
  final Map<int, int> bySender;
  final List<int> byHour;
  final List<int> byWeekday;
  final Map<AttachmentType, int> media;
  final List<MapEntry<String, int>> topWords;
  final int words;
  final DateTime? first;
  final DateTime? last;
  final DateTime? busiestDay;
  final int busiestDayCount;

  static final RegExp _word = RegExp(
    r"[\p{L}\p{N}][\p{L}\p{N}'-]*",
    unicode: true,
  );

  static const Set<String> _stopWords = {
    'и',
    'в',
    'во',
    'не',
    'что',
    'он',
    'на',
    'я',
    'с',
    'со',
    'как',
    'а',
    'то',
    'все',
    'она',
    'так',
    'его',
    'но',
    'да',
    'ты',
    'к',
    'у',
    'же',
    'вы',
    'за',
    'бы',
    'по',
    'только',
    'ее',
    'её',
    'мне',
    'было',
    'вот',
    'от',
    'меня',
    'еще',
    'ещё',
    'нет',
    'о',
    'из',
    'ему',
    'теперь',
    'когда',
    'даже',
    'ну',
    'ли',
    'если',
    'уже',
    'или',
    'ни',
    'быть',
    'был',
    'него',
    'до',
    'вас',
    'нибудь',
    'опять',
    'уж',
    'вам',
    'ведь',
    'там',
    'потом',
    'себя',
    'ничего',
    'ей',
    'может',
    'они',
    'тут',
    'где',
    'есть',
    'надо',
    'ней',
    'для',
    'мы',
    'тебя',
    'их',
    'чем',
    'была',
    'сам',
    'чтоб',
    'без',
    'будто',
    'чего',
    'раз',
    'тоже',
    'себе',
    'под',
    'будет',
    'ж',
    'тогда',
    'кто',
    'этот',
    'того',
    'потому',
    'этого',
    'какой',
    'совсем',
    'ним',
    'здесь',
    'этом',
    'один',
    'почти',
    'мой',
    'тем',
    'чтобы',
    'нее',
    'неё',
    'сейчас',
    'были',
    'куда',
    'зачем',
    'всех',
    'никогда',
    'можно',
    'при',
    'наконец',
    'два',
    'об',
    'другой',
    'хоть',
    'после',
    'над',
    'больше',
    'тот',
    'через',
    'эти',
    'нас',
    'про',
    'всего',
    'них',
    'какая',
    'много',
    'разве',
    'три',
    'эту',
    'моя',
    'впрочем',
    'хорошо',
    'свою',
    'этой',
    'перед',
    'иногда',
    'лучше',
    'чуть',
    'том',
    'нельзя',
    'такой',
    'им',
    'более',
    'всегда',
    'конечно',
    'всю',
    'между',
    'это',
    'щас',
    'просто',
    'вообще',
    'короче',
    'типа',
    'крч',
    'тебе',
  };

  static ChatStats compute(Iterable<CachedMessage> messages) {
    final bySender = <int, int>{};
    final byHour = List<int>.filled(24, 0);
    final byWeekday = List<int>.filled(7, 0);
    final media = <AttachmentType, int>{};
    final wordCounts = <String, int>{};
    final perDay = <int, int>{};
    var total = 0;
    var words = 0;
    int? firstTime;
    int? lastTime;

    for (final message in messages) {
      if (message.isControl || message.deleted) continue;
      total++;
      bySender.update(message.senderId, (v) => v + 1, ifAbsent: () => 1);
      final time = DateTime.fromMillisecondsSinceEpoch(message.time);
      byHour[time.hour]++;
      byWeekday[time.weekday - 1]++;
      final day = DateTime(
        time.year,
        time.month,
        time.day,
      ).millisecondsSinceEpoch;
      perDay.update(day, (v) => v + 1, ifAbsent: () => 1);
      if (firstTime == null || message.time < firstTime) {
        firstTime = message.time;
      }
      if (lastTime == null || message.time > lastTime) {
        lastTime = message.time;
      }
      for (final attachment
          in message.attachments ?? const <MessageAttachment>[]) {
        media.update(attachment.type, (v) => v + 1, ifAbsent: () => 1);
      }
      final text = message.text;
      if (text == null || text.isEmpty) continue;
      for (final match in _word.allMatches(text.toLowerCase())) {
        final word = match.group(0)!;
        words++;
        if (word.length < 3 || _stopWords.contains(word)) continue;
        if (int.tryParse(word) != null) continue;
        wordCounts.update(word, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    final topWords = wordCounts.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    MapEntry<int, int>? busiest;
    for (final entry in perDay.entries) {
      if (busiest == null || entry.value > busiest.value) busiest = entry;
    }

    return ChatStats._(
      total: total,
      bySender: bySender,
      byHour: byHour,
      byWeekday: byWeekday,
      media: media,
      topWords: topWords.take(15).toList(),
      words: words,
      first: firstTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(firstTime),
      last: lastTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastTime),
      busiestDay: busiest == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(busiest.key),
      busiestDayCount: busiest?.value ?? 0,
    );
  }

  int get activeDays {
    final from = first;
    final to = last;
    if (from == null || to == null) return 0;
    return to.difference(from).inDays + 1;
  }

  double get perDay => activeDays == 0 ? 0 : total / activeDays;

  List<MapEntry<int, int>> get topSenders =>
      bySender.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
