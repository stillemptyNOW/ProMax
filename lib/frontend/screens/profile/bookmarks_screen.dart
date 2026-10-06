import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/modules/chats.dart';
import '../../../core/security/double_bottom.dart';
import '../../../core/storage/bookmarks_store.dart';
import '../../../core/utils/format.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/letter_avatar.dart';
import '../chats/chat_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(MessageBookmark bookmark) {
    final chat = chats
        .chatsSnapshot(includeHidden: true)
        .where((c) => c.id == bookmark.chatId)
        .firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: bookmark.chatId,
          name: bookmark.chatName,
          imageUrl: chat?.iconUrl ?? '',
          chatType: chat?.type ?? (bookmark.chatId > 0 ? 'DIALOG' : 'CHAT'),
          initialMessageId: bookmark.messageId,
          initialMessageTime: bookmark.time,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Закладки',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<List<MessageBookmark>>(
          valueListenable: BookmarksStore.instance.items,
          builder: (context, stored, _) => ListenableBuilder(
            listenable: Listenable.merge([_query, DoubleBottom.listenable]),
            builder: (context, _) {
              final all = [
                for (final b in stored)
                  if (!DoubleBottom.hides(b.chatId)) b,
              ];
              final term = _query.text.trim().toLowerCase();
              final shown = term.isEmpty
                  ? all
                  : [
                      for (final b in all)
                        if (b.text.toLowerCase().contains(term) ||
                            b.chatName.toLowerCase().contains(term))
                          b,
                    ];
              final header = <Widget>[
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    hintText: 'Поиск по закладкам',
                    prefixIcon: const Icon(Symbols.search),
                    filled: true,
                    fillColor: cs.onSurface.withValues(alpha: 0.07),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (all.isEmpty)
                  const _BookmarksPlaceholder(
                    icon: Symbols.bookmarks,
                    title: 'Закладок пока нет',
                    subtitle: 'Зажми сообщение и выбери «В закладки»',
                  )
                else if (shown.isEmpty)
                  const _BookmarksPlaceholder(
                    icon: Symbols.search_off,
                    title: 'Ничего не нашлось',
                    subtitle: 'Попробуй другой запрос',
                  ),
              ];
              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                itemCount: header.length + shown.length,
                itemBuilder: (context, index) {
                  if (index < header.length) return header[index];
                  final bookmark = shown[index - header.length];
                  return Padding(
                    key: ValueKey(bookmark.key),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: ValueKey(bookmark.key),
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
                      onDismissed: (_) =>
                          BookmarksStore.instance.remove(bookmark),
                      child: _BookmarkCard(
                        bookmark: bookmark,
                        onTap: () => _open(bookmark),
                        onCopy: () async {
                          await Clipboard.setData(
                            ClipboardData(text: bookmark.text),
                          );
                          if (context.mounted) {
                            showCustomNotification(context, 'Скопировано');
                          }
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BookmarksPlaceholder extends StatelessWidget {
  const _BookmarksPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icon, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({
    required this.bookmark,
    required this.onTap,
    required this.onCopy,
  });

  final MessageBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onCopy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LetterAvatarFill(
                    name: bookmark.chatName,
                    seed: avatarSeedFor(bookmark.chatName),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bookmark.chatName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    formatChatListStamp(
                      DateTime.fromMillisecondsSinceEpoch(bookmark.time),
                    ),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                bookmark.text.isEmpty ? 'Вложение' : bookmark.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bookmark.text.isEmpty
                      ? cs.onSurfaceVariant
                      : cs.onSurface,
                  fontSize: 15,
                  height: 1.3,
                  fontStyle: bookmark.text.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
