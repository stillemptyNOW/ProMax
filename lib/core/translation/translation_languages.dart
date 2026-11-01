class TranslationLanguages {
  const TranslationLanguages._();

  static const Map<String, String> names = {
    'ru': 'Русский',
    'en': 'English',
    'uk': 'Українська',
    'be': 'Беларуская',
    'kk': 'Қазақша',
    'uz': 'O‘zbekcha',
    'ky': 'Кыргызча',
    'tg': 'Тоҷикӣ',
    'hy': 'Հայերեն',
    'ka': 'ქართული',
    'az': 'Azərbaycanca',
    'tr': 'Türkçe',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'it': 'Italiano',
    'pt': 'Português',
    'pl': 'Polski',
    'cs': 'Čeština',
    'nl': 'Nederlands',
    'sv': 'Svenska',
    'fi': 'Suomi',
    'el': 'Ελληνικά',
    'he': 'עברית',
    'ar': 'العربية',
    'fa': 'فارسی',
    'hi': 'हिन्दी',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'id': 'Bahasa Indonesia',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
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
