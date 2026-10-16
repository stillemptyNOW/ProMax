import 'dart:io';

import '../utils/logger.dart';
import '../utils/windows_registry.dart';

// #***! схемы которые вешаем на себя
const List<String> _schemes = ['promax', 'max'];

// #***! регистрация схем в системе, на мобилках это манифест
abstract class DesktopUrlScheme {
  static Future<void> register() async {
    try {
      if (Platform.isWindows) {
        await _registerWindows();
      } else if (Platform.isLinux) {
        await _registerLinux();
      }
    } catch (e) {
      logger.w('DesktopUrlScheme: регистрация не удалась: $e');
    }
  }

  static Future<void> _registerWindows() async {
    final registry = WindowsRegistry.currentUser;
    if (registry == null) return;
    final command = '"${Platform.resolvedExecutable}" "%1"';
    for (final scheme in _schemes) {
      final capitalized = '${scheme[0].toUpperCase()}${scheme.substring(1)}';
      final base = 'Software\\Classes\\$scheme';
      _ensure(registry, base, null, 'URL:$capitalized');
      _ensure(registry, base, 'URL Protocol', '');
      _ensure(registry, '$base\\shell\\open\\command', null, command);
    }
  }

  static void _ensure(
    WindowsRegistry registry,
    String key,
    String? valueName,
    String value,
  ) {
    if (registry.readString(key, valueName) == value) return;
    if (!registry.writeString(key, valueName, value)) {
      logger.w('DesktopUrlScheme: не записал $key');
    }
  }

  // #***! на линуксе .desktop файл и назначаем обработчиком
  static Future<void> _registerLinux() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final exe = Platform.resolvedExecutable;
    final appsDir = Directory('$home/.local/share/applications');
    await appsDir.create(recursive: true);

    const fileName = 'promax-url-handler.desktop';
    final mimeTypes = _schemes.map((s) => 'x-scheme-handler/$s').join(';');
    final desktop =
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=ProMax\n'
        'Exec="$exe" %u\n'
        'Terminal=false\n'
        'NoDisplay=true\n'
        'MimeType=$mimeTypes;\n';

    final file = File('${appsDir.path}/$fileName');
    if (!file.existsSync() || await file.readAsString() != desktop) {
      await file.writeAsString(desktop);
    }

    for (final scheme in _schemes) {
      await _run('xdg-mime', ['default', fileName, 'x-scheme-handler/$scheme']);
    }
    await _run('update-desktop-database', [appsDir.path]);
  }

  // #***! ошибки игнорим, без регистрации просто не будет диплинков
  static Future<void> _run(String executable, List<String> args) async {
    try {
      await Process.run(executable, args);
    } catch (_) {}
  }
}
