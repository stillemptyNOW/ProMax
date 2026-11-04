import 'package:flutter/foundation.dart';

enum AppIcon {
  defaultIcon(
    'default',
    'Классическая',
    'assets/promax_icon.png',
    'IconDefault',
  ),
  light('light', 'Светлая', 'assets/icons/promax_light.png', 'IconLight'),
  aurora('aurora', 'Аврора', 'assets/icons/promax_aurora.png', 'IconAurora'),
  sunset('sunset', 'Закат', 'assets/icons/promax_sunset.png', 'IconSunset'),
  glass('glass', 'Стекло', 'assets/icons/promax_glass.png', 'IconGlass'),
  halloween(
    'halloween',
    'Хэллоуин',
    'assets/icons/promax_halloween.png',
    'IconHalloween',
  ),
  newYear(
    'newyear',
    'Новый год',
    'assets/icons/promax_newyear.png',
    'IconNewYear',
  ),
  christmas(
    'christmas',
    'Рождество',
    'assets/icons/promax_christmas.png',
    'IconChristmas',
  ),
  valentine(
    'valentine',
    '14 февраля',
    'assets/icons/promax_valentine.png',
    'IconValentine',
  ),
  womensday(
    'womensday',
    '8 марта',
    'assets/icons/promax_womensday.png',
    'IconWomensDay',
  ),
  victoryday(
    'victoryday',
    '9 мая',
    'assets/icons/promax_victoryday.png',
    'IconVictoryDay',
  );

  final String id;
  final String title;
  final String previewAsset;
  final String nativeName;

  const AppIcon(this.id, this.title, this.previewAsset, this.nativeName);

  String? get iosAlternateName => this == defaultIcon ? null : nativeName;

  static AppIcon? byId(String? id) {
    for (final icon in values) {
      if (icon.id == id) return icon;
    }
    return null;
  }

  static AppIcon? byNativeName(String? name) {
    for (final icon in values) {
      if (icon.nativeName == name) return icon;
    }
    return null;
  }
}

enum AppIconPlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  unsupported;

  static AppIconPlatform resolve({
    required bool web,
    required TargetPlatform target,
  }) {
    if (web) return unsupported;
    return switch (target) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.windows => windows,
      TargetPlatform.macOS => macos,
      TargetPlatform.linux => linux,
      TargetPlatform.fuchsia => unsupported,
    };
  }

  bool get canSwitch => this != unsupported;

  bool get isDesktop => this == windows || this == macos || this == linux;

  bool get readsAppliedIcon => this == android || this == ios;

  bool get resetsOnLaunch => isDesktop;

  bool get defersAutomaticSwitch => this == android;

  bool get closesOnManualSwitch => this == android;

  bool get sendsIconImage => this == macos || this == linux;
}

enum IconSeason {
  halloween(AppIcon.halloween, 10, 28),
  newYear(AppIcon.newYear, 12, 29),
  christmas(AppIcon.christmas, 1, 5),
  valentine(AppIcon.valentine, 2, 11),
  womensday(AppIcon.womensday, 3, 5),
  victoryday(AppIcon.victoryday, 5, 6);

  final AppIcon icon;
  final int startMonth;
  final int startDay;
  static const durationDays = 7;

  const IconSeason(this.icon, this.startMonth, this.startDay);

  SeasonPeriod? periodAt(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    for (final year in [day.year, day.year - 1]) {
      final start = DateTime(year, startMonth, startDay);
      final end = DateTime(year, startMonth, startDay + durationDays - 1);
      if (!day.isBefore(start) && !day.isAfter(end)) {
        return SeasonPeriod(this, year, end);
      }
    }
    return null;
  }

  static SeasonPeriod? activeAt(DateTime now) {
    for (final season in values) {
      final period = season.periodAt(now);
      if (period != null) return period;
    }
    return null;
  }
}

@immutable
class SeasonPeriod {
  final IconSeason season;
  final int year;
  final DateTime lastDay;

  const SeasonPeriod(this.season, this.year, this.lastDay);

  String get key => '${season.name}-$year';

  @override
  bool operator ==(Object other) =>
      other is SeasonPeriod && other.season == season && other.year == year;

  @override
  int get hashCode => Object.hash(season, year);
}

@immutable
class AppIconSelection {
  final AppIcon choice;
  final bool seasonal;
  final String? manualSeason;

  const AppIconSelection({
    this.choice = AppIcon.defaultIcon,
    this.seasonal = false,
    this.manualSeason,
  });

  SeasonPeriod? seasonalOverrideAt(DateTime now) {
    if (!seasonal) return null;
    final period = IconSeason.activeAt(now);
    if (period == null || period.key == manualSeason) return null;
    return period;
  }

  AppIcon effectiveAt(DateTime now) =>
      seasonalOverrideAt(now)?.season.icon ?? choice;

  AppIconSelection pick(AppIcon icon, DateTime now) => AppIconSelection(
    choice: icon,
    seasonal: seasonal,
    manualSeason: seasonal ? IconSeason.activeAt(now)?.key : null,
  );

  AppIconSelection withSeasonal(bool enabled) =>
      AppIconSelection(choice: choice, seasonal: enabled);

  @override
  bool operator ==(Object other) =>
      other is AppIconSelection &&
      other.choice == choice &&
      other.seasonal == seasonal &&
      other.manualSeason == manualSeason;

  @override
  int get hashCode => Object.hash(choice, seasonal, manualSeason);
}

abstract final class AppIconAutoSwitch {
  static AppIcon? target({
    required AppIconSelection selection,
    required AppIcon applied,
    required DateTime now,
    required String? autoApplied,
    required bool appliedResetsOnLaunch,
  }) {
    final effective = selection.effectiveAt(now);
    if (effective == applied) return null;
    final allowed =
        appliedResetsOnLaunch ||
        selection.seasonal ||
        autoApplied == applied.id;
    return allowed ? effective : null;
  }

  static AppIconSelection adopt({
    required AppIconSelection selection,
    required AppIcon applied,
    required String? autoApplied,
  }) {
    if (selection.seasonal || autoApplied == applied.id) return selection;
    if (selection.choice == applied) return selection;
    return AppIconSelection(choice: applied);
  }

  static String attemptKey(AppIcon target, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${target.id}@${now.year}-${two(now.month)}-${two(now.day)}';
  }
}
