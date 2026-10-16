import 'package:flutter/widgets.dart';

import '../../../core/utils/download_history.dart';
import '../../../core/utils/media_cache.dart';
import '../../../core/utils/save_file_as.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/sandbox_prompts.dart';

Future<bool?> saveMiniAppDownload({
  required MiniAppDownloadChoice choice,
  required String url,
  required String fileName,
  required int botId,
  required String sourceName,
  required String dialogTitle,
}) async {
  if (choice == MiniAppDownloadChoice.cancel) return null;
  final cacheName = 'webapp_${botId}_${url.hashCode & 0x7fffffff}_$fileName';
  if (choice == MiniAppDownloadChoice.keep) {
    final file = await MediaCache.keep(cacheName, url: url);
    if (file == null) return false;
    try {
      await DownloadHistory.record(
        DownloadMetadata(
          cacheName: MediaCache.keptName(cacheName),
          name: fileName,
          kind: downloadKindForName(fileName),
          sourceName: sourceName,
        ),
        file,
      );
    } catch (_) {}
    return true;
  }
  final file = await MediaCache.getOrDownload(cacheName, url);
  if (file == null) return false;
  final result = await saveFileAs(
    source: file,
    fileName: fileName,
    dialogTitle: dialogTitle,
  );
  if (result.cancelled) return null;
  return result.saved;
}

void reportMiniAppDownload(
  BuildContext? context,
  MiniAppDownloadChoice choice,
  bool? saved,
) {
  if (saved == null || context == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final message = !saved
      ? l10n.sandboxDownloadFailed
      : choice == MiniAppDownloadChoice.keep
      ? l10n.sandboxDownloadSaved
      : l10n.photoViewerFileSaved;
  showCustomNotification(context, message);
}
