import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

abstract final class ExternalTool {
  static final Map<String, String?> _resolved = {};

  static String? resolve(String name) =>
      _resolved.putIfAbsent(name, () => _find(name));

  @visibleForTesting
  static List<String> candidates(
    String name, {
    required String executable,
    required String searchPath,
    required bool windows,
  }) {
    final context = windows ? p.windows : p.posix;
    final fileName = windows ? '$name.exe' : name;
    final directories = <String>[
      context.dirname(executable),
      ...searchPath
          .split(windows ? ';' : ':')
          .map((entry) => entry.trim().replaceAll('"', ''))
          .where(
            (entry) =>
                entry.isNotEmpty &&
                context.isAbsolute(entry) &&
                !entry.startsWith(r'\\') &&
                !entry.startsWith('//'),
          ),
    ];
    return [for (final dir in directories) context.join(dir, fileName)];
  }

  static String? _find(String name) {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return null;
    final paths = candidates(
      name,
      executable: Platform.resolvedExecutable,
      searchPath: Platform.environment['PATH'] ?? '',
      windows: Platform.isWindows,
    );
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
