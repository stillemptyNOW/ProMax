import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/file_names.dart';

String _asLatin1(String s) => latin1.decode(utf8.encode(s));

void main() {
  test('ascii names are sent as is', () {
    expect(encodeUploadFilename('report_2026.xlsx'), 'report_2026.xlsx');
  });

  test('non-ascii names are percent encoded', () {
    final encoded = encodeUploadFilename('Отчёт итог.xlsx');
    expect(encoded.codeUnits.every((c) => c < 0x80), isTrue);
    expect(Uri.decodeComponent(encoded), 'Отчёт итог.xlsx');
  });

  test('latin1 mojibake is repaired', () {
    const name = 'Группа_ФКН_почта.xlsx';
    expect(repairFileName(_asLatin1(name)), name);
  });

  test('percent encoded names are decoded', () {
    expect(repairFileName(Uri.encodeComponent('Сводка.pdf')), 'Сводка.pdf');
  });

  test('normal names stay untouched', () {
    for (final name in ['café.txt', 'Отчёт.docx', 'a%b.txt', 'plain.zip']) {
      expect(repairFileName(name), name);
    }
  });
}
