import 'package:flutter/material.dart';

class LetterAvatarPalette {
  static const List<List<Color>> gradients = [
    [Color(0xFFFF885E), Color(0xFFFF516A)],
    [Color(0xFFFFCD6A), Color(0xFFFFA85C)],
    [Color(0xFF82B1FF), Color(0xFF665FFF)],
    [Color(0xFFA0DE7E), Color(0xFF54CB68)],
    [Color(0xFF53EDD6), Color(0xFF28C9B7)],
    [Color(0xFF72D5FD), Color(0xFF2A9EF1)],
    [Color(0xFFE0A2F3), Color(0xFFD669ED)],
    [Color(0xFFF7A1C4), Color(0xFFEE5C9C)],
  ];

  static List<Color> forSeed(int seed) =>
      gradients[(seed.abs() * 7 + (seed < 0 ? 3 : 0)) % gradients.length];
}

int avatarSeedFor(String name) {
  var hash = 0;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

String avatarInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  String first(String word) {
    final runes = word.characters;
    return runes.isEmpty ? '' : runes.first.toUpperCase();
  }

  final letters =
      first(words.first) + (words.length > 1 ? first(words[1]) : '');
  return letters.isEmpty ? '?' : letters;
}

class LetterAvatarFill extends StatelessWidget {
  const LetterAvatarFill({
    super.key,
    required this.name,
    required this.seed,
    required this.size,
    this.child,
  });

  final String name;
  final int seed;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = LetterAvatarPalette.forSeed(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child:
          child ??
          Text(
            avatarInitials(name),
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
    );
  }
}
