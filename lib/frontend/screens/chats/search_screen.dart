import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../main.dart';
import '../../../backend/modules/chats.dart';
import '../../../backend/modules/contacts.dart';
import '../../../backend/modules/messages.dart' show ContactCache;
import '../../../core/storage/app_database.dart';
import '../../../core/contacts/contact_labels.dart';
import '../../../core/utils/debouncer.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/promax_avatar.dart';
import '../../widgets/small_spinner.dart';
import '../../widgets/swipe_route.dart';
import '../contacts/open_contact_profile.dart';
import 'chat_screen.dart';

enum SearchScope { all, people, chats, messages }

enum SearchPeriod { any, day, week, month, year }

enum SearchSender { any, me, others }

enum SearchChatKind { any, dialogs, groups, channels }

const _scopeLabels = {
  SearchScope.all: 'Всё',
  SearchScope.people: 'Люди',
  SearchScope.chats: 'Чаты',
  SearchScope.messages: 'Сообщения',
};
const _periodLabels = {
  SearchPeriod.any: 'За всё время',
  SearchPeriod.day: 'Сегодня',
  SearchPeriod.week: 'Неделя',
  SearchPeriod.month: 'Месяц',
  SearchPeriod.year: 'Год',
};
const _senderLabels = {
  SearchSender.any: 'Любой отправитель',
  SearchSender.me: 'Я',
  SearchSender.others: 'Не я',
};
const _kindLabels = {
  SearchChatKind.any: 'Все чаты',
  SearchChatKind.dialogs: 'Личные',
  SearchChatKind.groups: 'Группы',
  SearchChatKind.channels: 'Каналы',
};

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  int _seq = 0;
  int? _accountId;

  bool _loading = false;
  PhoneLookupResult? _phoneResult;
  List<Map<String, dynamic>> _contacts = const [];
  List<Map<String, dynamic>> _chats = const [];
  List<MessageSearchHit> _messages = const [];
  Map<int, Map<String, dynamic>> _msgChatMeta = const {};
  List<ChatSearchHit> _public = const [];
  SearchScope _scope = SearchScope.all;
  SearchPeriod _period = SearchPeriod.any;
  SearchSender _sender = SearchSender.any;
  SearchChatKind _kind = SearchChatKind.any;

  bool get _messageFiltersActive =>
      _period != SearchPeriod.any ||
      _sender != SearchSender.any ||
      _kind != SearchChatKind.any;

  List<MessageSearchHit> get _filteredMessages {
    final now = DateTime.now();
    final from = switch (_period) {
      SearchPeriod.any => null,
      SearchPeriod.day => DateTime(now.year, now.month, now.day),
      SearchPeriod.week => now.subtract(const Duration(days: 7)),
      SearchPeriod.month => now.subtract(const Duration(days: 30)),
      SearchPeriod.year => now.subtract(const Duration(days: 365)),
    };
    final me = _accountId;
    return [
      for (final hit in _messages)
        if ((from == null || hit.time >= from.millisecondsSinceEpoch) &&
            (_sender == SearchSender.any ||
                (_sender == SearchSender.me) == (hit.senderId == me)) &&
            _kindMatches(hit.chatId))
          hit,
    ];
  }

  bool _kindMatches(int chatId) {
    if (_kind == SearchChatKind.any) return true;
    final type = _msgChatMeta[chatId]?['type'] as String?;
    return switch (_kind) {
      SearchChatKind.any => true,
      SearchChatKind.dialogs => type == null || type == 'DIALOG',
      SearchChatKind.groups => type == 'CHAT',
      SearchChatKind.channels => type == 'CHANNEL',
    };
  }

  Future<void> _pickFilter<T>(
    String title,
    Map<T, String> labels,
    T current,
    ValueChanged<T> onSelected,
  ) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final entry in labels.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == current
                    ? Icon(
                        Symbols.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => onSelected(picked));
  }

  Widget _filterBar(ColorScheme cs) {
    Widget pill(String label, bool active, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? cs.primary.withValues(alpha: 0.18)
                : cs.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? cs.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? cs.primary : cs.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Symbols.expand_more,
                size: 18,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        children: [
          pill(
            _scopeLabels[_scope]!,
            _scope != SearchScope.all,
            () => _pickFilter(
              'Что искать',
              _scopeLabels,
              _scope,
              (v) => _scope = v,
            ),
          ),
          pill(
            _periodLabels[_period]!,
            _period != SearchPeriod.any,
            () => _pickFilter(
              'Период',
              _periodLabels,
              _period,
              (v) => _period = v,
            ),
          ),
          pill(
            _senderLabels[_sender]!,
            _sender != SearchSender.any,
            () => _pickFilter(
              'Отправитель',
              _senderLabels,
              _sender,
              (v) => _sender = v,
            ),
          ),
          pill(
            _kindLabels[_kind]!,
            _kind != SearchChatKind.any,
            () => _pickFilter('Тип чата', _kindLabels, _kind, (v) => _kind = v),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    AppDatabase.loadActiveProfile().then((p) {
      if (mounted) _accountId = p?.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty) {
      _debounce.cancel();
      _seq++;
      setState(() {
        _loading = false;
        _phoneResult = null;
        _contacts = const [];
        _chats = const [];
        _messages = const [];
        _msgChatMeta = const {};
        _public = const [];
      });
      return;
    }
    if (_phoneResult != null) {
      setState(() => _phoneResult = null);
    }
    _debounce.run(_runSearch);
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final token = ++_seq;
    setState(() => _loading = true);

    final accountId = _accountId;
    final phoneQuery = _phoneCandidate(query);
    final serverMessagesFuture = chats.searchMessages(api, query);
    final publicFuture = chats.searchPublic(api, query);
    final phoneFuture = phoneQuery == null
        ? Future<PhoneLookupResult?>.value(null)
        : ContactsModule.findByPhone(api, phoneQuery);

    final contacts = accountId == null
        ? const <Map<String, dynamic>>[]
        : await AppDatabase.searchContacts(accountId, query);
    final localChats = accountId == null
        ? const <Map<String, dynamic>>[]
        : await AppDatabase.searchChatsByTitle(accountId, query);
    final localRows = accountId == null
        ? const <Map<String, dynamic>>[]
        : await AppDatabase.searchMessagesText(accountId, query);
    if (!mounted || token != _seq) return;
    final localHits = [
      for (final row in localRows)
        MessageSearchHit(
          chatId: row['chat_id'] as int,
          messageId: row['id']?.toString(),
          text: row['text'] as String?,
          time: row['time'] as int? ?? 0,
          senderId: row['sender_id'] as int? ?? 0,
        ),
    ];
    await _applyMessages(accountId, token, localHits);
    if (!mounted || token != _seq) return;
    setState(() {
      _contacts = contacts;
      _chats = localChats;
    });

    final serverHits = await serverMessagesFuture;
    final publicHits = await publicFuture;
    final phoneResult = await phoneFuture;
    if (!mounted || token != _seq) return;
    await _applyMessages(accountId, token, [...serverHits, ...localHits]);
    if (!mounted || token != _seq) return;
    final localChatIds = localChats.map((c) => c['id'] as int).toSet();
    setState(() {
      _phoneResult = phoneResult;
      _public = publicHits.where((c) => !localChatIds.contains(c.id)).toList();
      _loading = false;
    });
  }

  Future<void> _applyMessages(
    int? accountId,
    int token,
    List<MessageSearchHit> hits,
  ) async {
    final seen = <String>{};
    final messages = [
      for (final hit in hits)
        if (seen.add('${hit.chatId}:${hit.messageId ?? hit.time}')) hit,
    ]..sort((a, b) => b.time.compareTo(a.time));
    var meta = <int, Map<String, dynamic>>{};
    if (accountId != null && messages.isNotEmpty) {
      final ids = messages.map((m) => m.chatId).toSet().toList();
      final rows = await AppDatabase.loadChatsByIds(accountId, ids);
      meta = {for (final r in rows) r['id'] as int: r};
    }
    if (!mounted || token != _seq) return;
    setState(() {
      _messages = messages;
      _msgChatMeta = meta;
    });
  }

  ContactLabels _contactLabels(Map<String, dynamic> row) => contactLabels(
    idLabel: AppLocalizations.of(context)!.contactIdFallback('${row['id']}'),
    firstName: row['first_name'],
    lastName: row['last_name'],
    phone: row['phone'],
  );

  String _contactName(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) {
      final cached = ContactCache.get(id);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    return _contactLabels(row).title;
  }

  String _phoneResultName(PhoneLookupResult result) {
    return ContactCache.get(result.id) ??
        result.name ??
        AppLocalizations.of(context)!.userFallbackName(result.id);
  }

  ({String name, String? avatar, String type}) _chatIdentity(
    int chatId,
    String? type,
    String? title,
    String? iconUrl,
  ) {
    final fallbackType = type ?? 'CHAT';
    if (chatId == 0) {
      return (
        name: AppLocalizations.of(context)!.searchScreenSavedMessages,
        avatar: iconUrl,
        type: fallbackType,
      );
    }
    final me = _accountId ?? 0;
    final peer = me == 0 ? 0 : chatId ^ me;
    if ((type != null && type != 'DIALOG') || peer <= 0) {
      return (name: title ?? '', avatar: iconUrl, type: fallbackType);
    }
    final cachedName = ContactCache.get(peer);
    final cachedAvatar = ContactCache.getAvatar(peer);
    final known = cachedName != null && cachedName.isNotEmpty;
    return (
      name: known ? cachedName : (title ?? ''),
      avatar: (cachedAvatar != null && cachedAvatar.isNotEmpty)
          ? cachedAvatar
          : iconUrl,
      type: known ? 'DIALOG' : fallbackType,
    );
  }

  void _openChat(int chatId, String name, String? avatarUrl, String type) {
    pushSwipeable(
      context,
      (_) => ChatScreen(
        chatId: chatId,
        name: name,
        imageUrl: avatarUrl ?? '',
        chatType: type,
      ),
    );
  }

  void _openContact(Map<String, dynamic> row) {
    unawaited(
      openContactDialogProfile(
        context,
        contactId: row['id'] as int,
        name: _contactName(row),
        avatarUrl: row['base_url'] as String?,
      ),
    );
  }

  String? _phoneCandidate(String query) {
    if (!RegExp(r'^[+\d\s\-()]+$').hasMatch(query)) return null;
    final digits = query.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 5) return null;
    return query;
  }

  void _openPhoneResult(PhoneLookupResult result) {
    unawaited(
      openContactDialogProfile(
        context,
        contactId: result.id,
        name: _phoneResultName(result),
        avatarUrl: result.avatarUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _controller.text.trim();
    final hasResults =
        _phoneResult != null ||
        _contacts.isNotEmpty ||
        _chats.isNotEmpty ||
        _filteredMessages.isNotEmpty ||
        _public.isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Symbols.arrow_back, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          style: TextStyle(color: cs.onSurface, fontSize: 16),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.chatInfoMembersSearchHint,
            hintStyle: TextStyle(color: cs.outline, fontSize: 16),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: Icon(Symbols.close, color: cs.onSurfaceVariant),
              onPressed: () {
                _controller.clear();
                _onChanged('');
                _focusNode.requestFocus();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(cs),
          Expanded(child: _buildBody(cs, query, hasResults)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, String query, bool hasResults) {
    final l10n = AppLocalizations.of(context)!;
    if (query.isEmpty) {
      return _buildHint(cs, Symbols.search, l10n.searchScreenStartTyping);
    }
    if (!hasResults) {
      if (_loading) {
        return const Center(child: SmallSpinner(size: 36));
      }
      return _buildHint(cs, Symbols.search_off, l10n.contactsSearchEmpty);
    }
    final phoneResult = _scope == SearchScope.all && !_messageFiltersActive
        ? _phoneResult
        : null;
    final people =
        (_scope == SearchScope.all || _scope == SearchScope.people) &&
        !_messageFiltersActive;
    final chatsVisible =
        (_scope == SearchScope.all || _scope == SearchScope.chats) &&
        !_messageFiltersActive;
    final messagesVisible =
        _scope == SearchScope.all || _scope == SearchScope.messages;
    final messages = messagesVisible
        ? _filteredMessages
        : const <MessageSearchHit>[];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (phoneResult != null) ...[
          _sectionHeader(cs, l10n.searchScreenByPhone),
          _ResultTile(
            name: _phoneResultName(phoneResult),
            imageUrl: phoneResult.avatarUrl,
            subtitle: query,
            onTap: () => _openPhoneResult(phoneResult),
          ),
        ],
        if (people && _contacts.isNotEmpty) ...[
          _sectionHeader(cs, l10n.searchScreenContacts),
          for (final row in _contacts)
            _ResultTile(
              name: _contactName(row),
              imageUrl: row['base_url'] as String?,
              subtitle: _contactLabels(row).subtitle,
              onTap: () => _openContact(row),
            ),
        ],
        if (chatsVisible && _chats.isNotEmpty) ...[
          _sectionHeader(cs, l10n.searchScreenChats),
          for (final row in _chats) _localChatTile(row),
        ],
        if (messages.isNotEmpty) ...[
          _sectionHeader(
            cs,
            '${l10n.authLimitsSignupMessagesTitle} · ${messages.length}',
          ),
          for (final hit in messages) _messageTile(hit),
        ],
        if (chatsVisible && _public.isNotEmpty) ...[
          _sectionHeader(cs, l10n.searchScreenGlobalSearch),
          for (final hit in _public) _chatTile(hit),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _chatTile(ChatSearchHit hit) => _ResultTile(
    name: hit.title ?? '',
    imageUrl: hit.avatarUrl,
    subtitle: hit.subtitle,
    onTap: () => _openChat(hit.id, hit.title ?? '', hit.avatarUrl, hit.type),
  );

  Widget _localChatTile(Map<String, dynamic> row) {
    final chatId = row['id'] as int;
    final identity = _chatIdentity(
      chatId,
      (row['type'] as String?) ?? 'CHAT',
      row['title'] as String?,
      row['icon_url'] as String?,
    );
    return _ResultTile(
      name: identity.name,
      imageUrl: identity.avatar,
      onTap: () =>
          _openChat(chatId, identity.name, identity.avatar, identity.type),
    );
  }

  Widget _messageTile(MessageSearchHit hit) {
    final meta = _msgChatMeta[hit.chatId];
    final identity = _chatIdentity(
      hit.chatId,
      meta?['type'] as String?,
      meta?['title'] as String?,
      meta?['icon_url'] as String?,
    );
    final name = identity.name.isEmpty
        ? AppLocalizations.of(context)!.hubChatTileTitle
        : identity.name;
    return _ResultTile(
      name: name,
      imageUrl: identity.avatar,
      subtitle: hit.text?.trim(),
      onTap: () => _openChat(hit.chatId, name, identity.avatar, identity.type),
    );
  }

  Widget _sectionHeader(ColorScheme cs, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Text(
      title,
      style: TextStyle(
        color: cs.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildHint(ColorScheme cs, IconData icon, String text) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: cs.outline),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(color: cs.outline, fontSize: 15)),
      ],
    ),
  );
}

class _ResultTile extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback onTap;

  const _ResultTile({
    required this.name,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = subtitle?.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ProMaxAvatar(name: name, size: 48, imageUrl: imageUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty
                        ? AppLocalizations.of(context)!.searchScreenUntitled
                        : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
