import 'package:path/path.dart' as p;

bool isPastableLocalPath(
  String path, {
  required List<String> privateRoots,
  required bool windows,
}) {
  final context = windows ? p.windows : p.posix;
  if (path.isEmpty || !context.isAbsolute(path)) return false;
  if (windows) {
    final unified = path.replaceAll('/', r'\');
    if (unified.startsWith(r'\\')) return false;
  } else if (path.startsWith('//')) {
    return false;
  }
  final normalized = context.normalize(path);
  for (final root in privateRoots) {
    if (root.isEmpty) continue;
    final privateRoot = context.normalize(root);
    if (context.equals(privateRoot, normalized) ||
        context.isWithin(privateRoot, normalized)) {
      return false;
    }
  }
  return true;
}
