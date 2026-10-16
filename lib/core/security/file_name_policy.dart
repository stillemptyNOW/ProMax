import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const int maxFileNameBytes = 200;
const int _maxExtensionLength = 16;

final RegExp _forbiddenCharacters = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
final RegExp _invisibleCharacters = RegExp(
  r'[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
);
final RegExp _reservedDeviceNames = RegExp(
  r'^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³]|conin\$|conout\$|clock\$)$',
  caseSensitive: false,
);

const String _executableExtensionList =
    '.exe .com .scr .pif .cpl .msi .msp .mst .msc .bat .cmd .ps1 .psm1 '
    '.psd1 .ps1xml .psc1 .psc2 .vb .vbs .vbe .js .jse .wsf .wsh .ws .wsc '
    '.hta .lnk .url .scf .shb .shs .reg .inf .dll .ocx .sys .drv .xll .xlam '
    '.ppam .appx .appxbundle .msix .msixbundle .appinstaller .application '
    '.appref-ms .gadget .settingcontent-ms .library-ms .search-ms '
    '.searchconnector-ms .diagcab .chm .hlp .xbap .jnlp .iso .img .vhd '
    '.vhdx .jar .py .pyw .pyz .pyc .pl .rb .apk .apks .apkm .xapk .aab .app '
    '.command .tool .pkg .mpkg .dmg .scpt .scptd .applescript .workflow '
    '.terminal .fileloc .inetloc .webloc .sh .bash .zsh .csh .ksh .run '
    '.appimage .desktop .deb .rpm .snap .flatpak .flatpakref';

final Set<String> _executableExtensions = _executableExtensionList
    .split(' ')
    .toSet();

String sanitizeFileName(String raw, {String fallback = 'file'}) {
  var name = raw
      .replaceAll(_invisibleCharacters, '')
      .replaceAll(_forbiddenCharacters, '_');
  name = _trimEdges(name);
  name = _limitLength(name);
  name = _trimEdges(name);
  if (_reservedDeviceNames.hasMatch(_stemOf(name))) name = '_$name';
  return name.isEmpty ? fallback : name;
}

String? riskyExtensionOf(String name) {
  final extension = p.extension(sanitizeFileName(name)).toLowerCase();
  if (extension.isEmpty) return null;
  return _executableExtensions.contains(extension) ? extension : null;
}

bool isRiskyFileName(String name) => riskyExtensionOf(name) != null;

File fileInside(String directory, String fileName) {
  final root = p.normalize(p.absolute(directory));
  final target = p.normalize(p.join(root, sanitizeFileName(fileName)));
  if (!p.isWithin(root, target)) {
    throw FileSystemException('Имя файла выходит за пределы папки', fileName);
  }
  return File(target);
}

Future<File> availableFileIn(String directory, String fileName) async {
  var target = fileInside(directory, fileName);
  if (!await target.exists()) return target;
  final name = p.basename(target.path);
  final extension = p.extension(name);
  final stem = p.basenameWithoutExtension(name);
  var suffix = 2;
  while (await target.exists()) {
    target = fileInside(directory, '$stem ($suffix)$extension');
    suffix++;
  }
  return target;
}

String _stemOf(String name) {
  final dot = name.indexOf('.');
  final stem = dot < 0 ? name : name.substring(0, dot);
  return stem.trimRight();
}

String _trimEdges(String name) {
  var start = 0;
  var end = name.length;
  while (start < end && _isEdgeJunk(name.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isEdgeJunk(name.codeUnitAt(end - 1))) {
    end--;
  }
  return name.substring(start, end);
}

bool _isEdgeJunk(int unit) => unit == 0x2E || unit == 0x20 || unit == 0xA0;

String _limitLength(String name) {
  if (utf8.encode(name).length <= maxFileNameBytes) return name;
  var extension = p.extension(name);
  if (extension.length > _maxExtensionLength) extension = '';
  final stem = name.substring(0, name.length - extension.length);
  final budget = maxFileNameBytes - utf8.encode(extension).length;
  final kept = StringBuffer();
  var used = 0;
  for (final rune in stem.runes) {
    final char = String.fromCharCode(rune);
    final size = utf8.encode(char).length;
    if (used + size > budget) break;
    kept.write(char);
    used += size;
  }
  return '$kept$extension';
}
