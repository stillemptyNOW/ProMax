import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_icon_catalog.dart';

void main() {
  group('IconSeason', () {
    test('Хэллоуин длится с 24 октября по 2 ноября включительно', () {
      expect(IconSeason.activeAt(DateTime(2026, 10, 23, 23, 59)), isNull);
      expect(
        IconSeason.activeAt(DateTime(2026, 10, 24))?.key,
        'halloween-2026',
      );
      expect(
        IconSeason.activeAt(DateTime(2026, 11, 2, 23, 59))?.key,
        'halloween-2026',
      );
      expect(IconSeason.activeAt(DateTime(2026, 11, 3)), isNull);
    });

    test('Новый год переходит через смену года', () {
      expect(IconSeason.activeAt(DateTime(2026, 12, 19)), isNull);
      expect(IconSeason.activeAt(DateTime(2026, 12, 20))?.key, 'newYear-2026');
      expect(IconSeason.activeAt(DateTime(2027, 1, 1))?.key, 'newYear-2026');
      final last = IconSeason.activeAt(DateTime(2027, 1, 10, 22));
      expect(last?.key, 'newYear-2026');
      expect(last?.lastDay, DateTime(2027, 1, 10));
      expect(IconSeason.activeAt(DateTime(2027, 1, 11)), isNull);
    });
  });

  group('AppIconSelection', () {
    final halloween = DateTime(2026, 10, 30);
    final november = DateTime(2026, 11, 10);
    final winter = DateTime(2027, 1, 5);

    test('без сезонного режима всегда выбранная иконка', () {
      const selection = AppIconSelection(choice: AppIcon.aurora);
      expect(selection.effectiveAt(halloween), AppIcon.aurora);
      expect(selection.effectiveAt(winter), AppIcon.aurora);
    });

    test('сезон подменяет иконку и потом возвращает выбор', () {
      const selection = AppIconSelection(
        choice: AppIcon.aurora,
        seasonal: true,
      );
      expect(selection.effectiveAt(halloween), AppIcon.halloween);
      expect(selection.effectiveAt(november), AppIcon.aurora);
      expect(selection.effectiveAt(winter), AppIcon.newYear);
    });

    test('ручной выбор в сезон держится до конца этого сезона', () {
      const base = AppIconSelection(choice: AppIcon.aurora, seasonal: true);
      final picked = base.pick(AppIcon.glass, halloween);
      expect(picked.choice, AppIcon.glass);
      expect(picked.manualSeason, 'halloween-2026');
      expect(picked.effectiveAt(DateTime(2026, 11, 1)), AppIcon.glass);
      expect(picked.effectiveAt(november), AppIcon.glass);
      expect(picked.effectiveAt(winter), AppIcon.newYear);
      expect(picked.effectiveAt(DateTime(2027, 10, 25)), AppIcon.halloween);
    });

    test('ручной выбор вне сезона и без режима не помечает сезон', () {
      const base = AppIconSelection(choice: AppIcon.aurora, seasonal: true);
      expect(base.pick(AppIcon.glass, november).manualSeason, isNull);
      const off = AppIconSelection(choice: AppIcon.aurora);
      expect(off.pick(AppIcon.glass, halloween).manualSeason, isNull);
    });

    test('включение режима сбрасывает ручную отметку', () {
      const selection = AppIconSelection(
        choice: AppIcon.glass,
        seasonal: true,
        manualSeason: 'halloween-2026',
      );
      final off = selection.withSeasonal(false);
      expect(off.manualSeason, isNull);
      expect(off.withSeasonal(true).effectiveAt(halloween), AppIcon.halloween);
    });
  });

  group('AppIconAutoSwitch', () {
    final halloween = DateTime(2026, 10, 30);
    final november = DateTime(2026, 11, 10);
    const seasonal = AppIconSelection(choice: AppIcon.aurora, seasonal: true);

    AppIcon? target(
      AppIconSelection selection,
      AppIcon applied,
      DateTime now, {
      String? autoApplied,
      bool transient = false,
    }) => AppIconAutoSwitch.target(
      selection: selection,
      applied: applied,
      now: now,
      autoApplied: autoApplied,
      appliedResetsOnLaunch: transient,
    );

    test('переключает только когда цель отличается', () {
      expect(target(seasonal, AppIcon.aurora, halloween), AppIcon.halloween);
      expect(target(seasonal, AppIcon.halloween, halloween), isNull);
      expect(target(seasonal, AppIcon.halloween, november), AppIcon.aurora);
    });

    test('после выключения режима убирает только свою сезонную иконку', () {
      final off = seasonal.withSeasonal(false);
      expect(
        target(off, AppIcon.halloween, halloween, autoApplied: 'halloween'),
        AppIcon.aurora,
      );
      expect(target(off, AppIcon.halloween, halloween), isNull);
    });

    test('на десктопе иконка восстанавливается при каждом запуске', () {
      const off = AppIconSelection(choice: AppIcon.glass);
      expect(
        target(off, AppIcon.defaultIcon, november, transient: true),
        AppIcon.glass,
      );
      expect(target(off, AppIcon.defaultIcon, november), isNull);
    });

    test(
      'без сезонного режима принимаем иконку, которую показывает система',
      () {
        const off = AppIconSelection(choice: AppIcon.aurora);
        expect(
          AppIconAutoSwitch.adopt(
            selection: off,
            applied: AppIcon.defaultIcon,
            autoApplied: null,
          ).choice,
          AppIcon.defaultIcon,
        );
        expect(
          AppIconAutoSwitch.adopt(
            selection: seasonal,
            applied: AppIcon.halloween,
            autoApplied: null,
          ),
          seasonal,
        );
        expect(
          AppIconAutoSwitch.adopt(
            selection: off,
            applied: AppIcon.halloween,
            autoApplied: 'halloween',
          ),
          off,
        );
      },
    );

    test('попытка автосмены помечается датой, чтобы не зациклиться', () {
      expect(
        AppIconAutoSwitch.attemptKey(AppIcon.newYear, DateTime(2027, 1, 5, 9)),
        'newyear@2027-01-05',
      );
      expect(
        AppIconAutoSwitch.attemptKey(AppIcon.newYear, DateTime(2027, 1, 5, 21)),
        AppIconAutoSwitch.attemptKey(AppIcon.newYear, DateTime(2027, 1, 5, 9)),
      );
    });
  });

  test('возможности платформ', () {
    AppIconPlatform on(TargetPlatform target, {bool web = false}) =>
        AppIconPlatform.resolve(web: web, target: target);

    expect(on(TargetPlatform.android, web: true), AppIconPlatform.unsupported);
    expect(AppIconPlatform.unsupported.canSwitch, isFalse);
    for (final target in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      expect(on(target).canSwitch, isTrue, reason: '$target');
    }
    final android = on(TargetPlatform.android);
    expect(android.defersAutomaticSwitch, isTrue);
    expect(android.closesOnManualSwitch, isTrue);
    expect(android.readsAppliedIcon, isTrue);
    expect(on(TargetPlatform.iOS).readsAppliedIcon, isTrue);
    expect(on(TargetPlatform.iOS).defersAutomaticSwitch, isFalse);
    for (final desktop in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      final platform = on(desktop);
      expect(platform.isDesktop, isTrue);
      expect(platform.resetsOnLaunch, isTrue);
      expect(platform.closesOnManualSwitch, isFalse);
    }
    expect(on(TargetPlatform.windows).sendsIconImage, isFalse);
    expect(on(TargetPlatform.macOS).sendsIconImage, isTrue);
    expect(on(TargetPlatform.linux).sendsIconImage, isTrue);
  });
}
