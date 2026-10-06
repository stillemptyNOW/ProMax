import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/storage/quick_replies_store.dart';
import '../../widgets/connection_status.dart';
import '../chats/quick_replies_sheet.dart';

class QuickRepliesScreen extends StatelessWidget {
  const QuickRepliesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = QuickRepliesStore.instance;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Шаблоны ответов',
        backgroundColor: cs.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addQuickReply(context),
        icon: const Icon(Symbols.add),
        label: const Text('Шаблон'),
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<List<String>>(
          valueListenable: store.items,
          builder: (context, items, _) {
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.quickreply,
                        size: 56,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Шаблонов пока нет',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Они вставляются в сообщение из меню ProMax в любом чате',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: items.length,
              onReorderItem: store.move,
              itemBuilder: (context, index) {
                final text = items[index];
                return Padding(
                  key: ValueKey(text),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey('dismiss-$text'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Symbols.delete, color: cs.onError),
                    ),
                    onDismissed: (_) => store.removeAt(index),
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const Icon(Symbols.quickreply),
                        title: Text(
                          text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Symbols.drag_indicator),
                        ),
                        onTap: () async {
                          final edited = await editQuickReply(
                            context,
                            initial: text,
                          );
                          if (edited != null) await store.update(index, edited);
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
