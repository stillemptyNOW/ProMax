import 'package:flutter/foundation.dart';

import 'persisted_setting.dart';

// #***! скругления как в мобильном телеге или как в десктопном
enum BubbleStyle { promax, mobile, desktop }

// #***! настройка стиля пузыря
class AppBubbleShape {
  static const prefKey = 'app_bubble_shape';

  static final _setting = PersistedEnum<BubbleStyle>(
    prefKey: prefKey,
    defaultValue: BubbleStyle.promax,
    encode: (value) => value.name,
    decode: _parse,
  );

  static ValueNotifier<BubbleStyle> get current => _setting.current;

  static Future<BubbleStyle> load() => _setting.load();

  static Future<void> save(BubbleStyle style) => _setting.save(style);

  static BubbleStyle _parse(String? val) =>
      enumFromName(BubbleStyle.values, val, BubbleStyle.promax);

  // #***! подписи для настроек
  static String label(BubbleStyle style) {
    switch (style) {
      case BubbleStyle.promax:
        return 'ProMax';
      case BubbleStyle.mobile:
        return 'TG Mobile';
      case BubbleStyle.desktop:
        return 'TG Desktop';
    }
  }
}
