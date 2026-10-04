import 'build_profile.dart';

// #***! источник обновлений
abstract final class UpdateConfig {
  static const String repository = 'stillemptyNOW/ProMax';
  static const String apiUrl =
      'https://api.github.com/repos/$repository/releases?per_page=1';

  // #***! в App Store сборке проверка обновлений не используется
  static bool get isConfigured => !BuildProfile.isAppStoreBuild;

  // #***! добавляем метку минуты для обхода промежуточного кеша
  static Uri get manifestUri => Uri.parse(
    apiUrl,
  ).replace(queryParameters: {'per_page': '1', 't': _cacheBuster});

  static String get downloadsPage => 'https://github.com/$repository/releases';

  static String get _cacheBuster =>
      (DateTime.now().millisecondsSinceEpoch ~/ 60000).toString();
}
