import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_design.dart';
import '../../../core/hub/hub_content.dart';
import '../../../core/utils/link_opener.dart';
import '../../../l10n/app_localizations.dart';
import '../liquid_glass.dart';
import 'hub_kind_style.dart';

class HubRichBody extends StatefulWidget {
  const HubRichBody({super.key, required this.text, this.style});
  final String text;
  final TextStyle? style;
  @override
  State<HubRichBody> createState() => _HubRichBodyState();
}

class _HubRichBodyState extends State<HubRichBody> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _release() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _release();
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    final linkColor = Theme.of(context).colorScheme.primary;
    final blocks = HubRichText.parse(widget.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (block.bullet)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, left: 2),
                    child: Text('•', style: base),
                  ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: base,
                      children: [
                        for (final span in block.spans)
                          _span(context, span, linkColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  InlineSpan _span(BuildContext context, HubSpan span, Color linkColor) {
    switch (span.style) {
      case HubSpanStyle.plain:
        return TextSpan(text: span.text);
      case HubSpanStyle.bold:
        return TextSpan(
          text: span.text,
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
      case HubSpanStyle.link:
        final recognizer = TapGestureRecognizer()
          ..onTap = () => openExternalUrl(context, span.url!);
        _recognizers.add(recognizer);
        return TextSpan(
          text: span.text,
          recognizer: recognizer,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
        );
    }
  }
}

class HubAnnouncementCard extends StatelessWidget {
  const HubAnnouncementCard({
    super.key,
    required this.text,
    required this.meta,
    required this.footer,
    this.unread = false,
    this.pinned = false,
    this.animate = true,
    this.maxBodyLines,
    this.onAction,
    this.onTap,
    this.onLongPress,
  });
  final String text;
  final HubMeta meta;
  final String footer;
  final bool unread;
  final bool pinned;
  final bool animate;
  final int? maxBodyLines;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = _surface(context);
    if (!animate || MediaQuery.of(context).disableAnimations) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: card,
    );
  }

  Widget _surface(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = meta.kind.accent(scheme);
    final radius = BorderRadius.circular(22);
    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: _content(context, accent),
      ),
    );
    final wash = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: content,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ValueListenableBuilder<bool>(
        valueListenable: AppDesign.classic,
        builder: (context, classic, _) => classic
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: radius,
                ),
                child: wash,
              )
            : GlassSurface(
                liquid: true,
                borderRadius: radius,
                frostTint: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
                glassTint: accent.withValues(alpha: 0.08),
                child: wash,
              ),
      ),
    );
  }

  Widget _content(BuildContext context, Color accent) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta.image.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                meta.image,
                fit: BoxFit.cover,
                cacheWidth: 900,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: accent.withValues(alpha: 0.12),
                  child: Icon(meta.kind.icon, color: accent, size: 40),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(meta.kind.icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meta.kind.label(l10n),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (pinned)
                    Icon(
                      Symbols.push_pin,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  if (unread)
                    Container(
                      key: const ValueKey('hub_unread_dot'),
                      margin: const EdgeInsets.only(left: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              if (meta.title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  meta.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              maxBodyLines == null
                  ? HubRichBody(text: text)
                  : Text(
                      HubRichText.plain(text),
                      maxLines: maxBodyLines,
                      overflow: TextOverflow.ellipsis,
                    ),
              if (meta.hasButton && onAction != null) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.18),
                    foregroundColor: accent,
                  ),
                  child: Text(meta.buttonLabel),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                footer,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
