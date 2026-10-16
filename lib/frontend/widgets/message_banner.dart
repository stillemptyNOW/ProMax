import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'promax_avatar.dart';

const Duration _bannerDuration = Duration(seconds: 5);

OverlayEntry? _activeBanner;

void showMessageBanner(
  OverlayState overlay, {
  required String title,
  required String text,
  required VoidCallback onTap,
  String? avatarUrl,
  int? userId,
}) {
  _removeBanner(_activeBanner);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => MessageBanner(
      title: title,
      text: text,
      avatarUrl: avatarUrl,
      userId: userId,
      onTap: () {
        _removeBanner(entry);
        onTap();
      },
      onDismissed: () => _removeBanner(entry),
    ),
  );
  _activeBanner = entry;
  overlay.insert(entry);
}

void _removeBanner(OverlayEntry? entry) {
  if (entry == null) return;
  if (identical(_activeBanner, entry)) _activeBanner = null;
  if (!entry.mounted) return;
  entry
    ..remove()
    ..dispose();
}

class MessageBanner extends StatefulWidget {
  const MessageBanner({
    super.key,
    required this.title,
    required this.text,
    required this.onTap,
    required this.onDismissed,
    this.avatarUrl,
    this.userId,
    this.duration = _bannerDuration,
  });

  final String title;
  final String text;
  final String? avatarUrl;
  final int? userId;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final Duration duration;

  @override
  State<MessageBanner> createState() => _MessageBannerState();
}

class _MessageBannerState extends State<MessageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    if (_hovered) {
      _restartTimer();
      return;
    }
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top + 12;
    return Positioned(
      top: top,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, minWidth: 240),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _hovered = true,
            onExit: (_) => _hovered = false,
            child: Dismissible(
              key: const ValueKey('message_banner'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => widget.onDismissed(),
              child: _BannerCard(
                title: widget.title,
                text: widget.text,
                avatarUrl: widget.avatarUrl,
                userId: widget.userId,
                colors: cs,
                onTap: widget.onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.title,
    required this.text,
    required this.colors,
    required this.onTap,
    this.avatarUrl,
    this.userId,
  });

  final String title;
  final String text;
  final String? avatarUrl;
  final int? userId;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: colors.surfaceContainerHigh.withValues(alpha: 0.94),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                child: Row(
                  children: [
                    ProMaxAvatar(
                      name: title,
                      imageUrl: avatarUrl,
                      userId: userId,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
