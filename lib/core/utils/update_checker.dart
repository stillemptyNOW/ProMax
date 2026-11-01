import '../config/update_channel.dart';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/update_config.dart';

// #***! файл релиза, имя ссылка размер и sha256
class UpdateAsset {
  final String name;
  final String url;
  final int size;
  final String sha256;

  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  static UpdateAsset? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final url = raw['url'];
    if (name is! String || url is! String) return null;
    if (name.isEmpty || url.isEmpty) return null;
    final size = raw['size'];
    final digest = raw['sha256'];
    return UpdateAsset(
      name: name,
      url: url,
      size: size is int ? size : 0,
      sha256: digest is String ? digest.trim().toLowerCase() : '',
    );
  }
}

class ReleaseNotes {
  final String tag;
  final String version;
  final int? build;
  final String title;
  final String body;

  const ReleaseNotes({
    required this.tag,
    required this.version,
    required this.build,
    required this.title,
    required this.body,
  });

  bool get isEmpty => body.trim().isEmpty;
}

// #***! манифест с бакета
class AppUpdateInfo {
  final String version;
  final int? build;
  final String tag;
  final String url;
  final String notes;
  final List<UpdateAsset> assets;
  final List<ReleaseNotes> releaseNotes;

  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.tag,
    required this.url,
    required this.notes,
    required this.assets,
    this.releaseNotes = const [],
  });

  AppUpdateInfo withReleaseNotes(List<ReleaseNotes> notes) => AppUpdateInfo(
    version: version,
    build: build,
    tag: tag,
    url: url,
    notes: this.notes,
    assets: assets,
    releaseNotes: List.unmodifiable(notes),
  );

  // #***! APK выбираем по суффиксу имени
  UpdateAsset? assetWithSuffix(String suffix) => assetMatching(suffix: suffix);

  UpdateAsset? assetMatching({String prefix = '', required String suffix}) {
    for (final asset in assets) {
      if (asset.name.startsWith(prefix) && asset.name.endsWith(suffix)) {
        return asset;
      }
    }
    return null;
  }

  // #***! пустые поля дефолтим, кривой манифест игнорим целиком
  static AppUpdateInfo? tryParse(Map<String, dynamic> manifest) {
    final version = (manifest['version'] as String?)?.trim();
    if (version == null || version.isEmpty) return null;

    final rawBuild = manifest['build'];
    final build = rawBuild is int
        ? rawBuild
        : int.tryParse('${rawBuild ?? ''}');

    final tag = (manifest['tag'] as String?)?.trim();
    final url = (manifest['url'] as String?)?.trim();

    final rawAssets = manifest['assets'];
    final assets = <UpdateAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        final asset = UpdateAsset.tryParse(entry);
        if (asset != null) assets.add(asset);
      }
    }

    return AppUpdateInfo(
      version: version,
      build: build,
      tag: tag == null || tag.isEmpty ? 'v$version' : tag,
      url: url == null || url.isEmpty ? UpdateConfig.downloadsPage : url,
      notes: (manifest['notes'] as String?)?.trim() ?? '',
      assets: assets,
    );
  }
}

// #***! итог ручной проверки
enum UpdateCheckStatus { updateAvailable, upToDate, failed }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final AppUpdateInfo? update;

  const UpdateCheckResult._(this.status, [this.update]);

  const UpdateCheckResult.updateAvailable(AppUpdateInfo update)
    : this._(UpdateCheckStatus.updateAvailable, update);

  const UpdateCheckResult.upToDate() : this._(UpdateCheckStatus.upToDate);

  const UpdateCheckResult.failed() : this._(UpdateCheckStatus.failed);
}

({String version, int? build})? parseReleaseTag(String tag) {
  final match = RegExp(
    r'^v?(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?(?:\+(\d+))?',
  ).firstMatch(tag.trim());
  if (match == null) return null;
  return (version: match.group(1)!, build: int.tryParse(match.group(2) ?? ''));
}

typedef _PublishedRelease = ({
  Map<Object?, Object?> release,
  ({String version, int? build}) version,
});

bool isBetaRelease(Map<Object?, Object?> release) =>
    release['prerelease'] == true ||
    RegExp(
      r'(?:^|[.+-])(?:alpha|beta|rc|preview|nightly|dev)(?:[.+-]|$)',
      caseSensitive: false,
    ).hasMatch('${release['tag_name'] ?? ''}');

Iterable<_PublishedRelease> _publishedReleases(
  Object? releases, {
  bool includePrereleases = true,
}) sync* {
  final candidates = releases is List ? releases : [releases];
  for (final release in candidates.whereType<Map<Object?, Object?>>()) {
    if (release['draft'] == true ||
        (!includePrereleases && isBetaRelease(release))) {
      continue;
    }
    final tag = release['tag_name'];
    if (tag is! String) continue;
    final version = parseReleaseTag(tag);
    if (version == null) continue;
    yield (release: release, version: version);
  }
}

Map<Object?, Object?>? newestRelease(
  Object? releases, {
  bool includePrereleases = true,
}) {
  _PublishedRelease? newest;
  for (final entry in _publishedReleases(
    releases,
    includePrereleases: includePrereleases,
  )) {
    if (newest == null ||
        UpdateChecker._compareRelease(entry.version, newest.version) > 0) {
      newest = entry;
    }
  }
  return newest?.release;
}

List<ReleaseNotes> releaseNotesNewerThan(
  Object? releases, {
  required String currentVersion,
  required int? currentBuild,
  bool includePrereleases = true,
}) {
  final newer = [
    for (final entry in _publishedReleases(
      releases,
      includePrereleases: includePrereleases,
    ))
      if (UpdateChecker._isNewer(
        currentBase: currentVersion,
        currentBuild: UpdateChecker._normalizeBuild(currentBuild),
        remoteBase: entry.version.version,
        remoteBuild: UpdateChecker._normalizeBuild(entry.version.build),
      ))
        entry,
  ]..sort((a, b) => UpdateChecker._compareRelease(b.version, a.version));
  final seenTags = <String>{};
  final notes = <ReleaseNotes>[];
  for (final entry in newer) {
    final tag = entry.release['tag_name'] as String;
    if (!seenTags.add(tag)) continue;
    final name = entry.release['name'];
    final body = entry.release['body'];
    notes.add(
      ReleaseNotes(
        tag: tag,
        version: entry.version.version,
        build: entry.version.build,
        title: name is String && name.trim().isNotEmpty ? name.trim() : tag,
        body: body is String
            ? body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim()
            : '',
      ),
    );
  }
  return notes;
}

Map<String, dynamic> _manifestFromRelease(Map<Object?, Object?> release) {
  final tag = release['tag_name'] as String;
  final parsed = parseReleaseTag(tag)!;
  final rawAssets = release['assets'];
  final assets = <Map<String, Object?>>[];
  if (rawAssets is List) {
    for (final value in rawAssets.whereType<Map>()) {
      final name = value['name'];
      final url = value['browser_download_url'];
      if (name is! String || url is! String) continue;
      final digest = value['digest'];
      assets.add({
        'name': name,
        'url': url,
        'size': value['size'] is int ? value['size'] : 0,
        'sha256': digest is String
            ? digest.replaceFirst(RegExp(r'^sha256:'), '').toLowerCase()
            : '',
      });
    }
  }
  return {
    'version': parsed.version,
    'build': parsed.build,
    'tag': tag,
    'url': release['html_url'] is String
        ? release['html_url']
        : UpdateConfig.downloadsPage,
    'notes': release['body'] is String ? release['body'] : '',
    'assets': assets,
  };
}

AppUpdateInfo? updateFromReleases(
  Object? releases, {
  required String currentVersion,
  required int? currentBuild,
  bool includePrereleases = true,
}) {
  final release = newestRelease(
    releases,
    includePrereleases: includePrereleases,
  );
  if (release == null) {
    if (!includePrereleases && newestRelease(releases) != null) return null;
    throw const FormatException('No GitHub release has an app version');
  }
  final remote = AppUpdateInfo.tryParse(_manifestFromRelease(release));
  if (remote == null) return null;
  if (!UpdateChecker._isNewer(
    currentBase: currentVersion,
    currentBuild: UpdateChecker._normalizeBuild(currentBuild),
    remoteBase: remote.version,
    remoteBuild: UpdateChecker._normalizeBuild(remote.build),
  )) {
    return null;
  }
  return remote.withReleaseNotes(
    releaseNotesNewerThan(
      releases,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      includePrereleases: includePrereleases,
    ),
  );
}

// #***! проверка последнего публичного GitHub-релиза
abstract class UpdateChecker {
  static const String _userAgent = 'ProMaxUpdateChecker';

  static const String _lastCheckKey = 'update_last_check_ms';
  static const String _skippedTagKey = 'update_skipped_tag';
  // #***! сами проверяем не чаще раза в 6 часов
  static const Duration _checkInterval = Duration(hours: 6);
  static const Duration _timeout = Duration(seconds: 15);

  // #***! тянет манифест и отдаёт обновление только если оно новее
  static Future<AppUpdateInfo?> fetchLatest() async {
    if (!UpdateConfig.isConfigured) return null;

    await UpdateChannel.load();
    final info = await PackageInfo.fromPlatform();
    final releases = await _fetchReleases();
    return updateFromReleases(
      releases,
      currentVersion: info.version,
      currentBuild: int.tryParse(info.buildNumber),
      includePrereleases: UpdateChannel.beta.value,
    );
  }

  // #***! автопроверка, уважает интервал и пропустить эту версию
  static Future<AppUpdateInfo?> check({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!force) {
      final last = prefs.getInt(_lastCheckKey);
      if (last != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - last;
        if (elapsed >= 0 && elapsed < _checkInterval.inMilliseconds) {
          return null;
        }
      }
    }

    AppUpdateInfo? update;
    try {
      update = await fetchLatest();
    } catch (_) {
      return null;
    }

    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

    if (update == null) return null;

    if (!force && prefs.getString(_skippedTagKey) == update.tag) {
      return null;
    }

    return update;
  }

  // #***! ручная проверка из настроек, без интервала и пропусков
  /// Runs a user-initiated check without applying the automatic-check interval
  /// or the "skip this version" preference.
  static Future<UpdateCheckResult> checkNow() async {
    if (!UpdateConfig.isConfigured) {
      return const UpdateCheckResult.failed();
    }
    try {
      final update = await fetchLatest();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      return update == null
          ? const UpdateCheckResult.upToDate()
          : UpdateCheckResult.updateAvailable(update);
    } catch (_) {
      return const UpdateCheckResult.failed();
    }
  }

  // #***! пропустить версию помним по тегу
  static Future<void> skip(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedTagKey, tag);
  }

  // #***! манифест с no-cache иначе CDN отдаст старый
  static Future<Object?> _fetchReleases() async {
    final uri = UpdateConfig.manifestUri;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(uri);
      req.headers
        ..set(HttpHeaders.userAgentHeader, _userAgent)
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final resp = await req.close().timeout(_timeout);
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        throw HttpException(
          'Update manifest returned HTTP ${resp.statusCode}',
          uri: uri,
        );
      }
      final body = await resp
          .transform(const Utf8Decoder())
          .join()
          .timeout(_timeout);
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  // #***! в versionCode зашит код ABI, снимаем иначе сравнение врёт
  static const int _abiVersionCodeMultiplier = 1000;

  static int? _normalizeBuild(int? build) {
    if (build == null) return null;
    if (build >= _abiVersionCodeMultiplier) {
      return build % _abiVersionCodeMultiplier;
    }
    return build;
  }

  // #***! новее по версии или при равной по номеру сборки
  static bool _isNewer({
    required String currentBase,
    required int? currentBuild,
    required String remoteBase,
    required int? remoteBuild,
  }) {
    final cmp = _compareSemver(remoteBase, currentBase);
    if (cmp > 0) return true;
    if (cmp < 0) return false;
    if (remoteBuild != null && currentBuild != null) {
      return remoteBuild > currentBuild;
    }
    return false;
  }

  static int _compareRelease(
    ({String version, int? build}) a,
    ({String version, int? build}) b,
  ) {
    final cmp = _compareSemver(a.version, b.version);
    if (cmp != 0) return cmp;
    return (a.build ?? -1).compareTo(b.build ?? -1);
  }

  // #***! сравнение версий по числам без библиотеки
  static int _compareSemver(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb ? 1 : -1;
    }
    return 0;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
}
