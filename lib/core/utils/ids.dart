import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final Random _rng = Random.secure();

// #***! случайный hex для device_id и подобного
String randomHex(int bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

// #***! uuid v4 без библиотеки, биты версии проставляем руками
String uuidV4() =>
    _formatUuid(List<int>.generate(16, (_) => _rng.nextInt(256)), version: 4);

String uuidV5(String namespace, String name) {
  final digest = sha1.convert([..._uuidBytes(namespace), ...utf8.encode(name)]);
  return _formatUuid(digest.bytes.sublist(0, 16), version: 5);
}

List<int> _uuidBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) throw FormatException('Некорректный UUID', uuid);
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

String _formatUuid(List<int> bytes, {required int version}) {
  final b = List<int>.of(bytes);
  b[6] = (b[6] & 0x0f) | (version << 4);
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}
