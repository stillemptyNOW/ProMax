import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../security/incoming_paths.dart';
import 'clipboard_channel.dart';
import 'clipboard_media_types.dart';
import 'dib_image.dart';
import 'raw_clipboard_media.dart';
import 'win32_clipboard.dart';

// #***! вставка файлов и картинок из буфера
class ClipboardMedia {
  const ClipboardMedia._();

  // #***! на винде WinAPI, на остальных нативный канал
  static bool get supported {
    if (Platform.isWindows) return Win32Clipboard.instance != null;
    return Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isAndroid ||
        Platform.isIOS;
  }

  static Future<bool> hasMedia() async {
    if (Platform.isWindows) {
      return Win32Clipboard.instance?.hasMedia ?? false;
    }
    if (!supported) return false;
    return ClipboardChannel.hasMedia();
  }

  // #***! сначала файлы, потом PNG, потом виндовый DIB
  static Future<ClipboardMediaPayload?> read() async {
    final raw = await _readRaw();
    if (raw == null || raw.isEmpty) return null;

    if (raw.paths.isNotEmpty) {
      final files = <ClipboardFileRef>[];
      final privateRoots = await _privateRoots();
      for (final path in raw.paths) {
        if (privateRoots != null &&
            !isPastableLocalPath(
              path,
              privateRoots: privateRoots,
              windows: Platform.isWindows,
            )) {
          continue;
        }
        final file = File(path);
        if (!file.existsSync()) continue;
        files.add(
          ClipboardFileRef(
            path: path,
            name: _basename(path),
            size: file.lengthSync(),
          ),
        );
      }
      if (files.isNotEmpty) return ClipboardMediaPayload(files: files);
    }

    final png = raw.png;
    if (png != null && png.isNotEmpty) {
      return ClipboardMediaPayload(
        image: ClipboardImageData(
          bytes: png,
          extension: raw.imageExtension ?? '.png',
        ),
      );
    }

    // #***! DIB в PNG в отдельном изоляте
    final dib = raw.dib;
    if (dib != null && dib.isNotEmpty) {
      final decoded = await compute(dibToPng, dib);
      if (decoded != null && decoded.isNotEmpty) {
        return ClipboardMediaPayload(
          image: ClipboardImageData(bytes: decoded, extension: '.png'),
        );
      }
    }
    return null;
  }

  static Future<List<String>?> _privateRoots() async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    try {
      return [(await getApplicationSupportDirectory()).path];
    } catch (_) {
      return const [];
    }
  }

  static Future<RawClipboardMedia?> _readRaw() {
    if (Platform.isWindows) {
      final clipboard = Win32Clipboard.instance;
      if (clipboard == null) return Future.value();
      return clipboard.read();
    }
    if (!supported) return Future.value();
    return ClipboardChannel.read();
  }
}

String _basename(String path) {
  final separator = path.lastIndexOf(RegExp(r'[\\/]'));
  return separator < 0 ? path : path.substring(separator + 1);
}
