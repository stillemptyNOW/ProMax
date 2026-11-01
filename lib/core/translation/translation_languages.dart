class TranslationLanguages {
  const TranslationLanguages._();

  static const Map<String, String> names = {
    'ru': 'Русский',
    'en': 'Английский',
    'uk': 'Украинский',
    'be': 'Белорусский',
    'kk': 'Казахский',
    'uz': 'Узбекский',
    'ky': 'Киргизский',
    'tg': 'Таджикский',
    'hy': 'Армянский',
    'ka': 'Грузинский',
    'az': 'Азербайджанский',
    'tr': 'Турецкий',
    'de': 'Немецкий',
    'fr': 'Французский',
    'es': 'Испанский',
    'it': 'Итальянский',
    'pt': 'Португальский',
    'pl': 'Польский',
    'cs': 'Чешский',
    'nl': 'Нидерландский',
    'sv': 'Шведский',
    'fi': 'Финский',
    'el': 'Греческий',
    'he': 'Иврит',
    'ar': 'Арабский',
    'fa': 'Персидский',
    'hi': 'Хинди',
    'th': 'Тайский',
    'vi': 'Вьетнамский',
    'id': 'Индонезийский',
    'zh': 'Китайский',
    'ja': 'Японский',
    'ko': 'Корейский',
  };

  static const List<String> targets = [
    'ru',
    'en',
    'uk',
    'de',
    'fr',
    'es',
    'it',
    'pt',
    'tr',
    'pl',
    'zh',
    'ja',
    'ko',
    'ar',
  ];

  static String primary(String tag) =>
      tag.toLowerCase().split(RegExp('[-_]')).first;

  static String nameOf(String tag) => names[primary(tag)] ?? tag;
}
