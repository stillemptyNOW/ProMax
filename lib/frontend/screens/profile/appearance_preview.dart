part of 'appearance_screen.dart';

class _AppearancePreview extends StatefulWidget {
  const _AppearancePreview({required this.accent});

  final ValueNotifier<Color?> accent;

  @override
  State<_AppearancePreview> createState() => _AppearancePreviewState();
}

class _AppearancePreviewState extends State<_AppearancePreview> {
  late final _settings = Listenable.merge([
    widget.accent,
    AppBubbleShape.current,
    AppBubbleBehavior.current,
    AppChatChrome.current,
    AppComposerBackground.current,
    AppComposerStyle.current,
    AppDesign.classic,
    AppNavPillStyle.current,
    AppPillGradient.current,
    AppSpectrumBackground.current,
    AppVisualStyle.current,
  ]);
  ColorScheme? _customScheme;
  Color? _seed;
  var _expanded = true;

  ColorScheme _schemeFor(ColorScheme base) {
    final seed = widget.accent.value;
    if (seed == null) return base;
    if (seed != _seed || _customScheme?.brightness != base.brightness) {
      _seed = seed;
      _customScheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: base.brightness,
      );
    }
    return _customScheme!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final cs = _schemeFor(theme.colorScheme);
        final radius = AppDesign.classic.value ? 16.0 : 28.0;
        return Material(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: _expanded,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        Icon(Symbols.visibility, size: 19, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.appearanceLivePreview,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded ? Symbols.expand_less : Symbols.expand_more,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: const Duration(milliseconds: 200),
                child: _expanded
                    ? _PreviewCanvas(scheme: cs, l10n: l10n)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({required this.scheme, required this.l10n});

  final ColorScheme scheme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    final classic = AppDesign.classic.value;
    final spectrum = AppSpectrumBackground.current.value;
    final chrome = AppChatChrome.current.value;
    final liquidChrome = ChatChromeMaterial.isLiquid(chrome);
    final composer = AppComposerBackground.current.value;
    final glossyComposer = ComposerChrome.isGlossy(
      AppComposerStyle.current.value,
    );
    final nav = AppNavPillStyle.current.value;
    final navLiquid = NavPillMaterial.isLiquid(nav);
    final navFrost = NavPillMaterial.isFrost(nav);
    final gradient = AppPillGradient.current.value;
    final classicRadius = classic ? 10.0 : 22.0;

    final chromeColor = switch (chrome) {
      _ when liquidChrome => cs.surfaceContainerHigh.withValues(alpha: .60),
      ChatChromeStyle.color => cs.surfaceContainerHighest,
      ChatChromeStyle.blur => cs.surfaceContainerHigh.withValues(alpha: .88),
      ChatChromeStyle.none => Colors.transparent,
      _ => cs.surfaceContainerLow.withValues(alpha: .62),
    };
    final composerColor = ComposerMaterial.isLiquid(composer)
        ? cs.surfaceContainerHighest.withValues(alpha: .62)
        : ComposerMaterial.isFrost(composer)
        ? cs.surfaceContainerHigh.withValues(alpha: .73)
        : cs.surfaceContainerHighest;
    final navColor = navLiquid || navFrost
        ? cs.surfaceContainerHighest.withValues(alpha: navLiquid ? .68 : .84)
        : cs.surfaceContainerHighest;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            cs.surfaceContainerLow,
            cs.tertiaryContainer,
          ],
        ),
      ),
      child: CustomPaint(
        painter: _CanvasPattern(
          color: cs.onSurfaceVariant.withValues(alpha: .12),
          spectrum: spectrum,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SampleSurface(
                color: chromeColor,
                sheen: liquidChrome,
                radius: classicRadius,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      child: const Icon(Symbols.chat_bubble, size: 15),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ProMax',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                    Icon(Symbols.more_horiz, size: 19, color: cs.onSurface),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _Bubble(text: l10n.appearancePreviewHello, cs: cs, first: true),
              const SizedBox(height: 2),
              _Bubble(text: l10n.appearancePreviewHowIsIt, cs: cs),
              const SizedBox(height: 5),
              _Bubble(
                text: l10n.appearancePreviewNotBad,
                cs: cs,
                first: true,
                outgoing: true,
              ),
              const SizedBox(height: 10),
              _SampleSurface(
                color: composerColor,
                sheen:
                    (glossyComposer && gradient) ||
                    ComposerMaterial.isLiquid(composer),
                radius: glossyComposer ? 24 : 12,
                child: Row(
                  children: [
                    Icon(
                      Symbols.attach_file,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.composerHintMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      child: const Icon(Symbols.send, size: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: _SampleSurface(
                  color: navColor,
                  sheen: navLiquid || (!navFrost && gradient),
                  radius: classicRadius,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.chat_bubble, size: 15, color: cs.primary),
                      const SizedBox(width: 14),
                      Icon(Symbols.call, size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 14),
                      Icon(
                        Symbols.person,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
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

class _SampleSurface extends StatelessWidget {
  const _SampleSurface({
    required this.color,
    required this.sheen,
    required this.radius,
    required this.child,
  });

  final Color color;
  final bool sheen;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: sheen ? null : color,
      gradient: sheen
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, .19)!, color],
            )
          : null,
      border: sheen
          ? Border.all(color: Colors.white.withValues(alpha: .24))
          : null,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.cs,
    this.first = false,
    this.outgoing = false,
  });

  final String text;
  final ColorScheme cs;
  final bool first;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => Align(
    alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: outgoing ? cs.primaryContainer : cs.incomingBubble,
        borderRadius: computeBubbleRadius(
          isMe: outgoing,
          isTop: first,
          isBottom: outgoing || !first,
          style: AppBubbleShape.current.value,
          behavior: AppBubbleBehavior.current.value,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: outgoing ? cs.onPrimaryContainer : cs.onSurface,
          fontSize: 13,
          height: 1.2,
        ),
      ),
    ),
  );
}

class _CanvasPattern extends CustomPainter {
  const _CanvasPattern({required this.color, required this.spectrum});

  final Color color;
  final bool spectrum;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (spectrum) {
      for (double x = 10; x < size.width; x += 12) {
        final height = size.height * (.18 + (x % 47) / 100);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, (size.height - height) / 2, 5, height),
            const Radius.circular(3),
          ),
          paint,
        );
      }
      return;
    }
    for (double x = 10; x < size.width; x += 16) {
      for (double y = 10; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPattern oldDelegate) =>
      color != oldDelegate.color || spectrum != oldDelegate.spectrum;
}
