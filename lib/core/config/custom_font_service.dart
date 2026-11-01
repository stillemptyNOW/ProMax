import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'font_file_info.dart';
import 'font_metrics.dart';

class CustomFontService {
  static const String prefKey = 'app_custom_fonts';

  // #***! что уже зарегистрировано, второй раз грузить нельзя
  static final Set<String> _loaded = <String>{};
  static final Map<String, double> _metricScales = <String, double>{};

  static double metricScaleFor(String family) => _metricScales[family] ?? 1.0;

  // #***! список семейств в prefs, файлы в кэше
  static Future<List<String>> families() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefKey) ?? const <String>[];
  }

  static Future<void> preloadCached() async {
    final dir = await _cacheDir();
    final stored = await families();
    final present = <String>[];
    for (final family in stored) {
      final file = _fileFor(dir, family);
      if (!await file.exists()) continue;
      present.add(family);
      if (_loaded.contains(family)) continue;
      try {
        await _register(family, await file.readAsBytes());
      } catch (e) {
        logger.w('CustomFont: «$family» не загружен: $e');
      }
    }
    if (present.length == stored.length) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefKey, present);
  }

  static Future<String> addFromFile(Uint8List bytes, String fileName) async {
    if (!_isSfnt(bytes)) {
      throw const FormatException('not a ttf/otf/ttc font');
    }
    final family =
        FontFileInfo.familyName(bytes) ??
        FontFileInfo.familyFromFileName(fileName);
    final file = _fileFor(await _cacheDir(), family);
    await file.writeAsBytes(bytes, flush: true);
    if (!_loaded.contains(family)) await _register(family, bytes);
    await _persist(family);
    return family;
  }

  // #***! удаляем из списка и файл с диска
  static Future<void> removeFamily(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(prefKey) ?? <String>[];
    list.remove(family);
    await prefs.setStringList(prefKey, list);
    final file = _fileFor(await _cacheDir(), family);
    if (await file.exists()) await file.delete();
  }

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/custom_fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // #***! имя семейства в имя файла, лишнее в подчёркивания
  static File _fileFor(Directory dir, String family) {
    final safe = family.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ascii = RegExp(r'^[A-Za-z0-9 _-]*$').hasMatch(family);
    final name = ascii ? safe : '${safe}_${_stableHash(family)}';
    return File('${dir.path}/$name.ttf');
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // #***! проверяем что это шрифт и считаем метрику
  static Future<void> _register(String family, Uint8List bytes) async {
    if (!_isSfnt(bytes)) {
      throw const FormatException('not a ttf/otf/ttc font');
    }
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(family);
    final xHeight = FontMetrics.xHeightRatio(bytes);
    if (xHeight != null) {
      _metricScales[family] = FontMetrics.scaleForXHeight(xHeight);
    }
  }

  // #***! сигнатура шрифта, ttf otf true или ttc
  static bool _isSfnt(Uint8List b) {
    if (b.length < 4) return false;
    final tag = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    return tag == 0x00010000 ||
        tag == 0x4F54544F ||
        tag == 0x74727565 ||
        tag == 0x74746366;
  }

  static Future<void> _persist(String family) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(prefKey) ?? <String>[];
    if (!list.contains(family)) {
      list.add(family);
      await prefs.setStringList(prefKey, list);
    }
  }
}
