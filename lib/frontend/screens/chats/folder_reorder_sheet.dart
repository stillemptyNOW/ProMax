import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/models/chat_folder.dart';
import '../../../backend/modules/folders.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/sheet_helpers.dart';

Future<void> showFolderReorderSheet(BuildContext context) async {
  final accountId = await TokenStorage.getActiveAccountId();
  if (accountId == null || !context.mounted) return;
  final folders = await FoldersModule.loadFolders(accountId);
  if (folders.length < 2 || !context.mounted) return;
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surfaceContainerHigh,
    shape: kSheetShape,
    builder: (_) => _FolderReorderSheet(accountId: accountId, folders: folders),
  );
}

class _FolderReorderSheet extends StatefulWidget {
  const _FolderReorderSheet({required this.accountId, required this.folders});

  final int accountId;
  final List<ChatFolder> folders;

  @override
  State<_FolderReorderSheet> createState() => _FolderReorderSheetState();
}

class _FolderReorderSheetState extends State<_FolderReorderSheet> {
  late final List<ChatFolder> _order = [...widget.folders];
  bool _saving = false;

  bool get _changed {
    for (var i = 0; i < _order.length; i++) {
      if (_order[i].id != widget.folders[i].id) return true;
    }
    return false;
  }

  void _move(int oldIndex, int newIndex) {
    Haptics.selection();
    setState(() => _order.insert(newIndex, _order.removeAt(oldIndex)));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      await FoldersModule.reorderFolders(api, widget.accountId, [
        for (final folder in _order) folder.id,
      ]);
      Haptics.success();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      Haptics.error();
      if (!mounted) return;
      setState(() => _saving = false);
      showCustomNotification(
        context,
        l10n.folderReorderFailed(userFacingError(e, l10n)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
              child: Text(
                l10n.folderReorderTitle,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.folderReorderHint,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _saving ? (_, _) {} : _move,
                itemBuilder: (context, index) {
                  final folder = _order[index];
                  return ListTile(
                    key: ValueKey(folder.id),
                    leading: Icon(Symbols.folder, color: cs.primary),
                    title: Text(
                      folder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      enabled: !_saving,
                      child: Icon(
                        Symbols.drag_handle,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(l10n.folderReorderSave),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
