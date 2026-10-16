import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'logger.dart';
import '../security/app_lock.dart';
import '../security/file_name_policy.dart';
import '../security/mark_of_the_web.dart';

const _documentExport = MethodChannel(
  'io.github.stillemptynow.promax/media_export',
);

// #***! итог сохранить как, отмену отличаем от ошибки
class SaveFileAsResult {
  final bool saved;
  final bool cancelled;
  final String? path;
  final String? error;

  const SaveFileAsResult({
    required this.saved,
    this.cancelled = false,
    this.path,
    this.error,
  });
}

// #***! на андроиде системное сохранить файл, на остальных выбор папки и копирование
Future<SaveFileAsResult> saveFileAs({
  required File source,
  required String fileName,
  required String dialogTitle,
}) async {
  final name = sanitizeFileName(
    fileName,
    fallback: sanitizeFileName(p.basename(source.path)),
  );
  try {
    if (!kIsWeb && Platform.isAndroid) {
      return await _exportDocument(source, name);
    }
    final directory = await AppLock.instance.external(
      () => FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle),
    );
    if (directory == null) {
      return const SaveFileAsResult(saved: false, cancelled: true);
    }
    final target = await availableFileIn(directory, name);
    if (p.equals(p.absolute(source.path), p.absolute(target.path))) {
      return SaveFileAsResult(saved: true, path: target.path);
    }
    await source.copy(target.path);
    await MarkOfTheWeb.apply(target.path);
    return SaveFileAsResult(saved: true, path: target.path);
  } catch (error) {
    logger.w('[saveAs] $name: $error');
    return SaveFileAsResult(saved: false, error: error.toString());
  }
}

Future<SaveFileAsResult> _exportDocument(File source, String name) async {
  final uri = await _documentExport.invokeMethod<String>('saveAs', {
    'path': source.path,
    'name': name,
  });
  if (uri == null) return const SaveFileAsResult(saved: false, cancelled: true);
  return SaveFileAsResult(saved: true, path: uri);
}
