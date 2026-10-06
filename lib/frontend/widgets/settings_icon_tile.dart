import 'package:flutter/material.dart';

import '../../core/config/promax_nav.dart';

class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({
    super.key,
    required this.icon,
    this.plainColor,
    this.fill = 0,
  });

  final IconData icon;
  final Color? plainColor;
  final double fill;

  static const List<Color> _palette = [
    Color(0xFF0A84FF),
    Color(0xFF30B0C7),
    Color(0xFF34C759),
    Color(0xFFFF9F0A),
    Color(0xFFFF453A),
    Color(0xFFBF5AF2),
    Color(0xFF5E5CE6),
    Color(0xFFFF375F),
    Color(0xFF64D2FF),
    Color(0xFFAC8E68),
  ];

  static Color colorFor(IconData icon) =>
      _palette[(icon.codePoint * 31 + 7) % _palette.length];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: ProMaxIconTiles.enabled,
      builder: (context, tiles, _) {
        if (!tiles || plainColor != null) {
          return Icon(
            icon,
            color: plainColor ?? cs.onSurfaceVariant,
            size: 22,
            weight: 400,
          );
        }
        final color = colorFor(icon);
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(color, Colors.white, 0.12)!, color],
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 19,
            fill: 1,
            weight: 500,
          ),
        );
      },
    );
  }
}
