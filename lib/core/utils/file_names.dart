import 'dart:convert';

const _cp1252 = <int, int>{
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

final _percentByte = RegExp(r'%[0-9A-Fa-f]{2}');

String encodeUploadFilename(String name) {
  if (name.codeUnits.every((c) => c >= 0x20 && c < 0x7F && c != 0x25)) {
    return name;
  }
  return Uri.encodeComponent(name);
}

String repairFileName(String name) {
  var result = name;
  if (_percentByte.hasMatch(result)) {
    try {
      result = Uri.decodeComponent(result);
    } catch (_) {}
  }
  return _repairMojibake(result);
}

String _repairMojibake(String name) {
  var high = false;
  final bytes = <int>[];
  for (final rune in name.runes) {
    if (rune < 0x80) {
      bytes.add(rune);
      continue;
    }
    final byte = rune <= 0xFF ? rune : _cp1252[rune];
    if (byte == null) return name;
    high = true;
    bytes.add(byte);
  }
  if (!high) return name;
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return name;
  }
}
