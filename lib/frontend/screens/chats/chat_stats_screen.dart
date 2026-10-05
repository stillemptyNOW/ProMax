import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/modules/messages.dart';
import '../../../core/config/app_shape.dart';
import '../../../core/stats/chat_stats.dart';
import '../../../core/storage/app_database.dart';
import '../../../main.dart' show messagesModule;
import '../../../models/attachment.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';
import '../../widgets/small_spinner.dart';

class ChatStatsScreen extends StatefulWidget {
  const ChatStatsScreen({
    super.key,
    required this.accountId,
    required this.chatId,
    required this.title,
    this.preview,
  });

  final ChatStats? preview;
  final int accountId;
  final int chatId;
  final String title;

  @override
  State<ChatStatsScreen> createState() => _ChatStatsScreenState();
}

class _ChatStatsScreenState extends State<ChatStatsScreen> {
  ChatStats? _stats;
  bool _syncing = false;
  int _synced = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final preview = widget.preview;
    if (preview != null) {
      setState(() => _stats = preview);
      return;
    }
    final rows = await AppDatabase.loadMessages(
      widget.accountId,
      widget.chatId,
    );
    final stats = ChatStats.compute(rows.map(CachedMessage.fromDbRow));
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _syncHistory() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _synced = 0;
    });
    int? cursor;
    final seen = <String>{};
    for (var page = 0; page < 500 && mounted; page++) {
      final batch = await messagesModule.fetchHistory(
        widget.accountId,
        widget.chatId,
        fromTime: cursor,
        count: 100,
      );
      if (batch.isEmpty) break;
      var oldest = batch.first.time;
      var added = 0;
      for (final message in batch) {
        if (message.time < oldest) oldest = message.time;
        if (seen.add(message.id)) added++;
      }
      if (mounted) setState(() => _synced = seen.length);
      if (added == 0 || batch.length < 100) break;
      cursor = oldest - 1;
    }
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = _stats;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Статистика',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: stats == null
            ? const Center(child: SmallSpinner(size: 36))
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _range(stats),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  _Tiles(stats: stats),
                  const SizedBox(height: 12),
                  _SyncCard(
                    syncing: _syncing,
                    synced: _synced,
                    onSync: _syncHistory,
                  ),
                  if (stats.total > 0) ...[
                    if (stats.bySender.length > 1) ...[
                      const ProMaxSectionTitle('Кто пишет больше'),
                      SettingsPanel(child: _Senders(stats: stats)),
                    ],
                    const ProMaxSectionTitle('Активность по часам'),
                    SettingsPanel(
                      child: _Bars(
                        values: stats.byHour,
                        labels: [for (var h = 0; h < 24; h++) '$h'],
                        labelEvery: 3,
                        describe: (i, v) => '$i:00–$i:59 · $v',
                      ),
                    ),
                    const ProMaxSectionTitle('По дням недели'),
                    SettingsPanel(
                      child: _Bars(
                        values: stats.byWeekday,
                        labels: _weekdays,
                        labelEvery: 1,
                        describe: (i, v) => '${_weekdaysFull[i]} · $v',
                      ),
                    ),
                    if (stats.media.isNotEmpty) ...[
                      const ProMaxSectionTitle('Медиа и вложения'),
                      SettingsCard(
                        children: [
                          for (final entry in _mediaRows(stats))
                            _ValueRow(
                              icon: entry.$1,
                              label: entry.$2,
                              value: '${entry.$3}',
                            ),
                        ],
                      ),
                    ],
                    if (stats.topWords.isNotEmpty) ...[
                      const ProMaxSectionTitle('Частые слова'),
                      SettingsPanel(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final word in stats.topWords)
                              Chip(
                                label: Text('${word.key} · ${word.value}'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _weekdaysFull = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  static String _range(ChatStats stats) {
    final first = stats.first;
    final last = stats.last;
    if (first == null || last == null) return 'В памяти телефона нет сообщений';
    return 'С ${_date(first)} по ${_date(last)} · по сообщениям в памяти телефона';
  }

  static List<(IconData, String, int)> _mediaRows(ChatStats stats) {
    const names = {
      AttachmentType.photo: (Symbols.image, 'Фото'),
      AttachmentType.video: (Symbols.movie, 'Видео и кружки'),
      AttachmentType.audio: (Symbols.mic, 'Голосовые'),
      AttachmentType.file: (Symbols.description, 'Файлы'),
      AttachmentType.sticker: (Symbols.sentiment_satisfied, 'Стикеры'),
      AttachmentType.contact: (Symbols.contact_page, 'Контакты'),
      AttachmentType.location: (Symbols.location_on, 'Геопозиции'),
      AttachmentType.poll: (Symbols.ballot, 'Опросы'),
      AttachmentType.call: (Symbols.call, 'Звонки'),
    };
    final rows = <(IconData, String, int)>[];
    for (final entry in names.entries) {
      final count = stats.media[entry.key] ?? 0;
      if (count > 0) rows.add((entry.value.$1, entry.value.$2, count));
    }
    rows.sort((a, b) => b.$3.compareTo(a.$3));
    return rows;
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});

  final ChatStats stats;

  @override
  Widget build(BuildContext context) {
    final busiest = stats.busiestDay;
    final tiles = [
      ('Сообщений', '${stats.total}'),
      ('Слов', '${stats.words}'),
      ('В день', stats.perDay.toStringAsFixed(stats.perDay < 10 ? 1 : 0)),
      (
        'Рекорд за день',
        busiest == null
            ? '—'
            : '${stats.busiestDayCount} · ${busiest.day.toString().padLeft(2, '0')}.${busiest.month.toString().padLeft(2, '0')}',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        for (final tile in tiles) _Tile(label: tile.$1, value: tile.$2),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppShape.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.syncing,
    required this.synced,
    required this.onSync,
  });

  final bool syncing;
  final int synced;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => SettingsCard(
    children: [
      SettingsNavTile(
        icon: syncing ? Symbols.sync : Symbols.cloud_download,
        label: syncing
            ? 'Загружено сообщений: $synced'
            : 'Загрузить всю историю с сервера',
        onTap: syncing ? null : onSync,
      ),
    ],
  );
}

class _Senders extends StatelessWidget {
  const _Senders({required this.stats});

  final ChatStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final senders = stats.topSenders.take(8).toList();
    final max = senders.first.value;
    return Column(
      children: [
        for (final entry in senders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ContactCache.get(entry.key) ?? 'ID ${entry.key}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.value} · ${(entry.value * 100 / stats.total).round()}%',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: constraints.maxWidth * entry.value / max,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.values,
    required this.labels,
    required this.labelEvery,
    required this.describe,
  });

  final List<int> values;
  final List<String> labels;
  final int labelEvery;
  final String Function(int index, int value) describe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final max = values.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Tooltip(
                message: describe(i, values[i]),
                triggerMode: TooltipTriggerMode.tap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: max == 0 || values[i] == 0
                              ? 0
                              : (values[i] / max).clamp(0.03, 1.0),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: values[i] == max && max > 0
                                  ? cs.primary
                                  : cs.primary.withValues(alpha: 0.55),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 14,
                      child: i % labelEvery == 0
                          ? Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 10.5,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
