import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_icon_catalog.dart';

const _androidPackage = 'io.github.stillemptynow.promax';

List<String> _iosAlternateIcons() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final anchor = plist.indexOf('<key>CFBundleAlternateIcons</key>');
  expect(
    anchor,
    isNonNegative,
    reason: 'в Info.plist нет альтернативных иконок',
  );
  final tokens = RegExp(
    r'<dict>|</dict>|<key>([^<]*)</key>',
  ).allMatches(plist.substring(anchor));

  final names = <String>[];
  var depth = 0;
  var entered = false;
  for (final token in tokens) {
    final text = token.group(0)!;
    if (text == '<dict>') {
      depth++;
      entered = true;
    } else if (text == '</dict>') {
      depth--;
      if (entered && depth == 0) break;
    } else if (entered && depth == 1) {
      names.add(token.group(1)!);
    }
  }
  return names;
}

class _Alias {
  final String name;
  final String icon;
  final bool enabled;

  _Alias(this.name, this.icon, this.enabled);
}

List<_Alias> _launcherAliases() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final aliases = RegExp(
    r'<activity-alias([^>]*)>(.*?)</activity-alias>',
    dotAll: true,
  ).allMatches(manifest);
  String attribute(String attributes, String name) =>
      RegExp('android:$name="([^"]*)"').firstMatch(attributes)?.group(1) ?? '';
  return [
    for (final alias in aliases)
      if (alias.group(2)!.contains('android.intent.category.LAUNCHER'))
        _Alias(
          attribute(alias.group(1)!, 'name'),
          attribute(alias.group(1)!, 'icon'),
          attribute(alias.group(1)!, 'enabled') != 'false',
        ),
  ];
}

String _mainActivity() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  return RegExp(
    r'<activity\s[^>]*android:name="io\.github\.stillemptynow\.promax\.MainActivity".*?</activity>',
    dotAll: true,
  ).firstMatch(manifest)!.group(0)!;
}

List<String> _kotlinIconNames() {
  final source = File(
    'android/app/src/main/kotlin/io/github/stillemptynow/promax/MainActivity.kt',
  ).readAsStringSync();
  final start = source.indexOf('iconComponents = listOf(');
  expect(start, isNonNegative, reason: 'в MainActivity нет списка иконок');
  final body = source.substring(start, source.indexOf(')', start));
  return RegExp(r'"(\w+)"').allMatches(body).map((m) => m.group(1)!).toList();
}

String _resourceName(AppIcon icon) => icon == AppIcon.defaultIcon
    ? 'ic_launcher'
    : 'ic_launcher_${icon.nativeName.substring(4).toLowerCase()}';

void main() {
  final alternates = AppIcon.values.where((i) => i != AppIcon.defaultIcon);

  test('идентификаторы и нативные имена иконок уникальны', () {
    expect(
      AppIcon.values.map((i) => i.id).toSet().length,
      AppIcon.values.length,
    );
    expect(
      AppIcon.values.map((i) => i.nativeName).toSet().length,
      AppIcon.values.length,
    );
    for (final icon in AppIcon.values) {
      expect(AppIcon.byId(icon.id), icon);
      expect(AppIcon.byNativeName(icon.nativeName), icon);
    }
  });

  test('у каждой иконки есть превью в ассетах', () {
    for (final icon in AppIcon.values) {
      expect(File(icon.previewAsset).existsSync(), isTrue, reason: icon.id);
    }
  });

  test('дефолтная иконка на iOS — это primary, а не альтернативная', () {
    expect(
      AppIcon.defaultIcon.iosAlternateName,
      isNull,
      reason: 'setAlternateIconName ждёт nil, любое имя тут — APPLY_FAILED',
    );
  });

  test('альтернативные иконки iOS совпадают с каталогом и лежат в Runner', () {
    expect(
      _iosAlternateIcons(),
      alternates.map((i) => i.iosAlternateName).toList(),
    );
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    for (final icon in alternates) {
      for (final scale in ['2x', '3x']) {
        final file = '${icon.iosAlternateName}@$scale.png';
        expect(File('ios/Runner/$file').existsSync(), isTrue, reason: file);
        expect(
          '/* $file in Resources */,'.allMatches(project).length,
          1,
          reason: '$file не добавлен в Resources',
        );
      }
    }
  });

  test('launcher-алиасы Android совпадают с каталогом', () {
    final aliases = _launcherAliases();
    expect(
      aliases.map((a) => a.name).toList(),
      AppIcon.values.map((i) => '$_androidPackage.${i.nativeName}').toList(),
    );
    expect(aliases.where((a) => a.enabled).map((a) => a.name).toList(), [
      '$_androidPackage.${AppIcon.defaultIcon.nativeName}',
    ], reason: 'по умолчанию включён ровно один алиас');
    for (final icon in AppIcon.values) {
      final alias = aliases.firstWhere(
        (a) => a.name.endsWith('.${icon.nativeName}'),
      );
      expect(alias.icon, '@mipmap/${_resourceName(icon)}');
    }
    expect(
      _kotlinIconNames(),
      AppIcon.values.map((i) => i.nativeName).toList(),
    );
  });

  test('MainActivity не показывается в лаунчере сама по себе', () {
    final activity = _mainActivity();
    final filters = RegExp(
      r'<intent-filter>(.*?)</intent-filter>',
      dotAll: true,
    ).allMatches(activity).map((m) => m.group(1)!);
    for (final filter in filters) {
      if (!filter.contains('android.intent.category.LAUNCHER')) continue;
      expect(
        filter,
        contains('<data android:scheme='),
        reason: 'без data лаунчер покажет второй значок',
      );
    }
  });

  test('у каждой иконки Android есть mipmap и adaptive-слои', () {
    const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
    const res = 'android/app/src/main/res';
    for (final icon in AppIcon.values) {
      final name = _resourceName(icon);
      expect(
        File('$res/mipmap-anydpi-v26/$name.xml').existsSync(),
        isTrue,
        reason: name,
      );
      for (final density in densities) {
        expect(
          File('$res/mipmap-$density/$name.png').existsSync(),
          isTrue,
          reason: '$density/$name',
        );
      }
      final adaptive = File(
        '$res/mipmap-anydpi-v26/$name.xml',
      ).readAsStringSync();
      for (final drawable in RegExp(
        r'@drawable/(\w+)',
      ).allMatches(adaptive).map((m) => m.group(1)!)) {
        final exists =
            File('$res/drawable/$drawable.xml').existsSync() ||
            densities.every(
              (d) => File('$res/drawable-$d/$drawable.png').existsSync(),
            );
        expect(exists, isTrue, reason: '$name → $drawable');
      }
    }
  });

  test('Windows-ресурсы иконок совпадают с каталогом', () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    final header = File('windows/runner/resource.h').readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    for (final icon in AppIcon.values) {
      final suffix = icon.nativeName.substring(4).toUpperCase();
      final resource = icon == AppIcon.defaultIcon
          ? 'IDI_APP_ICON'
          : 'IDI_ICON_$suffix';
      final file = icon == AppIcon.defaultIcon
          ? 'app_icon.ico'
          : 'app_icon_${suffix.toLowerCase()}.ico';
      expect(header, contains('#define $resource '), reason: resource);
      expect(rc, contains(RegExp('$resource +ICON +"resources\\\\\\\\$file"')));
      expect(File('windows/runner/resources/$file').existsSync(), isTrue);
      expect(runner, contains('{"${icon.nativeName}", $resource}'));
    }
  });
}
