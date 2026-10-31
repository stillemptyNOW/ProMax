import 'package:flutter/material.dart';
import '../../core/config/app_shape.dart';
import '../../l10n/app_localizations.dart';
import 'chrome_glass.dart';

/// Shared confirmation dialog. Returns true if confirmed, false otherwise.
Future<bool> showConfirmDialog(
  BuildContext context, {
  String? title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  bool destructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final cancelText =
      cancelLabel ?? AppLocalizations.of(context)!.chatInfoActionCancel;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ChromeAlertDialog(
      title: title == null
          ? null
          : Text(title, style: TextStyle(color: cs.onSurface)),
      content: Text(
        message,
        style: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.errorContainer,
                  foregroundColor: cs.onErrorContainer,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ChromeAlertDialog extends StatelessWidget {
  const ChromeAlertDialog({
    super.key,
    this.title,
    required this.content,
    required this.actions,
  });

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(AppShape.dialog),
  );

  final Widget? title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ChromeGlassBuilder(
      builder: (context, liquid) => liquid ? _glass(context) : _opaque(context),
    );
  }

  Widget _opaque(BuildContext context) => AlertDialog(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: AppShape.dialogBorder,
    title: title,
    content: content,
    actions: actions,
  );

  Widget _glass(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final heading = title;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: _radius),
      child: IntrinsicWidth(
        child: ChromeGlassPanel(
          borderRadius: _radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (heading != null) ...[
                  DefaultTextStyle(
                    style: (theme.textTheme.headlineSmall ?? const TextStyle())
                        .copyWith(color: cs.onSurface),
                    child: heading,
                  ),
                  const SizedBox(height: 16),
                ],
                Flexible(
                  child: DefaultTextStyle(
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(color: cs.onSurfaceVariant),
                    child: content,
                  ),
                ),
                const SizedBox(height: 24),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
