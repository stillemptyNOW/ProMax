import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../core/config/app_fonts.dart';
import '../../core/config/app_shape.dart';
import '../../core/config/promax_glass.dart';
import '../widgets/hint_bubble.dart';

const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  },
);

// ignore: deprecated_member_use
const _progressTheme = ProgressIndicatorThemeData(year2023: false);

ColorScheme proMaxDarkScheme(ColorScheme base, {required bool amoled}) {
  if (amoled) {
    return base.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceBright: const Color(0xFF242424),
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF080808),
      surfaceContainer: const Color(0xFF101010),
      surfaceContainerHigh: const Color(0xFF161616),
      surfaceContainerHighest: const Color(0xFF1C1C1C),
      outlineVariant: const Color(0xFF2E2E2E),
    );
  }
  Color tone(double tint, int neutral) =>
      Color.alphaBlend(base.primary.withValues(alpha: tint), Color(neutral));
  return base.copyWith(
    surface: tone(0.05, 0xFF0D0D14),
    surfaceDim: tone(0.04, 0xFF0A0A10),
    surfaceBright: tone(0.12, 0xFF2C2C3A),
    surfaceContainerLowest: tone(0.03, 0xFF08080D),
    surfaceContainerLow: tone(0.06, 0xFF12121B),
    surfaceContainer: tone(0.07, 0xFF16161F),
    surfaceContainerHigh: tone(0.08, 0xFF1A1A26),
    surfaceContainerHighest: tone(0.12, 0xFF262636),
    outlineVariant: tone(0.10, 0xFF33333F),
  );
}

ColorScheme proMaxLightScheme(ColorScheme base) {
  Color tone(double tint, int neutral) =>
      Color.alphaBlend(base.primary.withValues(alpha: tint), Color(neutral));
  return base.copyWith(
    surface: tone(0.045, 0xFFF3F3F8),
    surfaceDim: tone(0.06, 0xFFE3E3EB),
    surfaceBright: tone(0.01, 0xFFFFFFFF),
    surfaceContainerLowest: tone(0.01, 0xFFFFFFFF),
    surfaceContainerLow: tone(0.02, 0xFFFBFBFE),
    surfaceContainer: tone(0.035, 0xFFF7F7FB),
    surfaceContainerHigh: tone(0.015, 0xFFFFFFFF),
    surfaceContainerHighest: tone(0.07, 0xFFE9E9F0),
    outlineVariant: tone(0.08, 0xFFD6D6E0),
  );
}

ThemeData buildProMaxTheme({
  required ColorScheme scheme,
  required String fontId,
  required ProMaxGlassTheme glass,
}) {
  final cs = scheme;
  final display = AppFonts.displayFamily(fontId);
  final family = AppFonts.resolve(fontId).fontFamily;
  final textTheme = AppFonts.textTheme(
    fontId,
    ThemeData(brightness: cs.brightness).textTheme,
  );
  final fieldRadius = BorderRadius.circular(AppShape.field);
  final menuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppShape.menu),
    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
  );
  const pill = StadiumBorder();
  const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 12);
  final buttonText = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  final titleStyle = TextStyle(
    fontFamily: display,
    color: cs.onSurface,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  return withM3ETheme(
    ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      pageTransitionsTheme: _pageTransitions,
      progressIndicatorTheme: _progressTheme,
      tooltipTheme: HintBubbleStyle.tooltipTheme(cs),
      extensions: [AppDisplayFont(display), glass],
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: titleStyle,
        iconTheme: IconThemeData(color: cs.onSurface),
        actionsIconTheme: IconThemeData(color: cs.onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.dialog),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        titleTextStyle: titleStyle.copyWith(fontSize: 21),
        contentTextStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurfaceVariant,
          fontSize: 15,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        modalBackgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: Colors.black.withValues(alpha: 0.42),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppShape.sheet),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.35),
        dragHandleSize: const Size(36, 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: menuShape,
        textStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurface,
          fontSize: 15,
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          shape: WidgetStatePropertyAll(menuShape),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: cs.onSurface.withValues(alpha: 0.06),
        hoverColor: cs.onSurface.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        labelStyle: TextStyle(fontFamily: family, color: cs.onSurfaceVariant),
        floatingLabelStyle: TextStyle(
          fontFamily: family,
          color: cs.primary,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: cs.error.withValues(alpha: 0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: cs.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: pill,
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          textStyle: buttonText,
          elevation: 0,
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          textStyle: buttonText,
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: cs.onSurface.withValues(alpha: 0.08),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minLeadingWidth: 24,
        horizontalTitleGap: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.tile),
        ),
        titleTextStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurfaceVariant,
          fontSize: 13.5,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.card),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : cs.outlineVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? cs.primary
              : cs.surfaceContainerHighest,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? cs.onPrimary
              : cs.onSurfaceVariant,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: cs.onSurfaceVariant, width: 1.6),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(
          fontFamily: family,
          color: cs.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: pill,
          side: BorderSide(color: cs.outlineVariant),
          selectedBackgroundColor: cs.primaryContainer,
          selectedForegroundColor: cs.onPrimaryContainer,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: TextStyle(
          fontFamily: family,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: family,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(4),
        thumbColor: WidgetStatePropertyAll(
          cs.onSurface.withValues(alpha: 0.28),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withValues(alpha: 0.28),
        selectionHandleColor: cs.primary,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.dialog),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.dialog),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: cs.primary,
        textColor: cs.onPrimary,
      ),
    ),
  );
}
