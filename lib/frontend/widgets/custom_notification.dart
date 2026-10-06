import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'toast_placement.dart';

const Duration _defaultNotificationDuration = Duration(milliseconds: 2600);
const double _bottomGap = 72;

OverlayEntry? _activeNotification;

void showCustomNotification(
  BuildContext context,
  String message, {
  Duration? duration,
}) {
  showCustomNotificationOnOverlay(
    Overlay.of(context),
    message,
    duration: duration,
  );
}

void showCustomNotificationOnOverlay(
  OverlayState overlay,
  String message, {
  Duration? duration,
}) {
  final total = duration ?? _defaultNotificationDuration;
  _removeNotification(_activeNotification);
  final entry = OverlayEntry(
    builder: (context) => CustomNotification(message: message, duration: total),
  );
  _activeNotification = entry;
  overlay.insert(entry);
  Future.delayed(total, () => _removeNotification(entry));
}

void _removeNotification(OverlayEntry? entry) {
  if (entry == null) return;
  if (identical(_activeNotification, entry)) _activeNotification = null;
  if (!entry.mounted) return;
  entry
    ..remove()
    ..dispose();
}

class CustomNotification extends StatefulWidget {
  final String message;
  final Duration duration;
  const CustomNotification({
    required this.message,
    this.duration = _defaultNotificationDuration,
    super.key,
  });

  @override
  State<CustomNotification> createState() => _CustomNotificationState();
}

class _CustomNotificationState extends State<CustomNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.9, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        ),
      );
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    final fadeOutDelay = widget.duration - _controller.reverseDuration!;
    Future.delayed(
      fadeOutDelay > Duration.zero ? fadeOutDelay : Duration.zero,
      () {
        if (mounted) _controller.reverse();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = cs.inverseSurface.withValues(alpha: 0.9);
    return ToastBottomPositioned(
      left: 12,
      right: 12,
      minBottom: _bottomGap,
      bandHeight: 48,
      minWidth: 160,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onInverseSurface,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
