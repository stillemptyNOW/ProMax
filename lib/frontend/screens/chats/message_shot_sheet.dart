import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/custom_notification.dart';
import '../../widgets/promax_ui.dart';

@immutable
class MessageShotItem {
  const MessageShotItem({
    required this.text,
    required this.mine,
    required this.sender,
    required this.time,
  });

  final String text;
  final bool mine;
  final String sender;
  final DateTime time;
}

enum MessageShotStyle {
  theme('Тема', Symbols.palette),
  dark('Тёмный', Symbols.dark_mode),
  light('Светлый', Symbols.light_mode),
  aurora('Аврора', Symbols.gradient);

  const MessageShotStyle(this.title, this.icon);

  final String title;
  final IconData icon;
}

Future<void> showMessageShotSheet(
  BuildContext context, {
  required String title,
  required List<MessageShotItem> items,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
  builder: (_) => _MessageShotSheet(title: title, items: items),
);

class _MessageShotSheet extends StatefulWidget {
  const _MessageShotSheet({required this.title, required this.items});

  final String title;
  final List<MessageShotItem> items;

  @override
  State<_MessageShotSheet> createState() => _MessageShotSheetState();
}

class _MessageShotSheetState extends State<_MessageShotSheet> {
  final GlobalKey _boundary = GlobalKey();
  MessageShotStyle _style = MessageShotStyle.theme;
  bool _names = true;
  bool _times = true;
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/promax_shot_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')]);
    } catch (e) {
      if (mounted) showCustomNotification(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Скриншот сообщений',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            RepaintBoundary(
              key: _boundary,
              child: MessageShotCard(
                title: widget.title,
                items: widget.items,
                style: _style,
                names: _names,
                times: _times,
              ),
            ),
            const ProMaxSectionTitle('Фон'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in MessageShotStyle.values)
                  ProMaxChoiceChip(
                    icon: style.icon,
                    label: style.title,
                    selected: style == _style,
                    onTap: () => setState(() => _style = style),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Имена отправителей'),
              value: _names,
              onChanged: (value) => setState(() => _names = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Время'),
              value: _times,
              onChanged: (value) => setState(() => _times = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Symbols.ios_share),
                label: const Text('Поделиться картинкой'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageShotCard extends StatelessWidget {
  const MessageShotCard({
    super.key,
    required this.title,
    required this.items,
    required this.style,
    required this.names,
    required this.times,
  });

  final String title;
  final List<MessageShotItem> items;
  final MessageShotStyle style;
  final bool names;
  final bool times;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = switch (style) {
      MessageShotStyle.theme => cs.brightness == Brightness.dark,
      MessageShotStyle.dark || MessageShotStyle.aurora => true,
      MessageShotStyle.light => false,
    };
    final background = switch (style) {
      MessageShotStyle.theme => [
        Color.alphaBlend(cs.primary.withValues(alpha: 0.18), cs.surface),
        cs.surface,
      ],
      MessageShotStyle.dark => [
        const Color(0xFF1B1D24),
        const Color(0xFF07070A),
      ],
      MessageShotStyle.light => [
        const Color(0xFFF4F5FA),
        const Color(0xFFE3E6F0),
      ],
      MessageShotStyle.aurora => [
        const Color(0xFF5B3FE0),
        const Color(0xFF0E8FB0),
      ],
    };
    final ink = dark ? Colors.white : const Color(0xFF111217);
    final incoming = dark ? Colors.white.withValues(alpha: 0.12) : Colors.white;
    final outgoing = style == MessageShotStyle.theme
        ? cs.primary
        : (dark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB));
    final outgoingInk = style == MessageShotStyle.theme
        ? cs.onPrimary
        : Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: background,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              _ShotBubble(
                item: items[i],
                showName:
                    names &&
                    !items[i].mine &&
                    (i == 0 ||
                        items[i - 1].sender != items[i].sender ||
                        items[i - 1].mine),
                showTime: times,
                color: items[i].mine ? outgoing : incoming,
                ink: items[i].mine ? outgoingInk : ink,
                accent: dark
                    ? const Color(0xFF8AB4FF)
                    : const Color(0xFF2563EB),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'ProMax',
                style: TextStyle(
                  color: ink.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShotBubble extends StatelessWidget {
  const _ShotBubble({
    required this.item,
    required this.showName,
    required this.showTime,
    required this.color,
    required this.ink,
    required this.accent,
  });

  final MessageShotItem item;
  final bool showName;
  final bool showTime;
  final Color color;
  final Color ink;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final time =
        '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: item.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.68,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(item.mine ? 18 : 6),
              bottomRight: Radius.circular(item.mine ? 6 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    item.sender,
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(item.text, style: TextStyle(color: ink, fontSize: 15)),
              if (showTime)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    time,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
