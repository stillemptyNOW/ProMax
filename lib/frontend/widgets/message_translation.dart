import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/translation/message_translator.dart';
import '../../core/translation/translation_backend.dart';
import '../../core/translation/translation_settings.dart';
import '../../l10n/app_localizations.dart';
import 'custom_notification.dart';
import 'small_spinner.dart';

String translationTargetFor(BuildContext context) => TranslationSettings
    .instance
    .targetFor(Localizations.localeOf(context).languageCode);

Future<void> translateMessageFromMenu(
  BuildContext context, {
  required int accountId,
  required int chatId,
  required String messageId,
  required String text,
}) async {
  final translator = MessageTranslator.instance;
  final key = MessageTranslator.keyOf(accountId, chatId, messageId);
  final outcome = await translator.translate(
    key,
    text,
    target: translationTargetFor(context),
  );
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final message = switch (outcome) {
    TranslateOutcome.translated => null,
    TranslateOutcome.sameLanguage => l10n.translationSameLanguage,
    TranslateOutcome.unavailable => l10n.translationUnavailable,
    TranslateOutcome.failed => translationFailureText(
      l10n,
      translator.stateOf(key).failure,
    ),
  };
  if (message != null) showCustomNotification(context, message);
}

String translationFailureText(
  AppLocalizations l10n,
  TranslationFailure? failure,
) => switch (failure) {
  TranslationFailure.needsWifi => l10n.translationNeedsWifi,
  TranslationFailure.unsupported => l10n.translationUnsupported,
  TranslationFailure.undetermined => l10n.translationUndetermined,
  _ => l10n.translationFailed,
};

class MessageTranslationScope extends StatefulWidget {
  final int accountId;
  final int chatId;
  final String messageId;
  final String sourceText;
  final bool isMe;
  final Widget Function(MessageTranslationState state) builder;

  const MessageTranslationScope({
    super.key,
    required this.accountId,
    required this.chatId,
    required this.messageId,
    required this.sourceText,
    required this.isMe,
    required this.builder,
  });

  @override
  State<MessageTranslationScope> createState() =>
      _MessageTranslationScopeState();
}

class _MessageTranslationScopeState extends State<MessageTranslationScope> {
  final _settings = TranslationSettings.instance;
  bool _dependenciesReady = false;

  String get _key => MessageTranslator.keyOf(
    widget.accountId,
    widget.chatId,
    widget.messageId,
  );

  @override
  void initState() {
    super.initState();
    _settings.autoChats.addListener(_autoTranslate);
    _settings.targetLanguage.addListener(_targetChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _autoTranslate();
  }

  @override
  void didUpdateWidget(MessageTranslationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceText != widget.sourceText ||
        oldWidget.messageId != widget.messageId ||
        oldWidget.chatId != widget.chatId) {
      _autoTranslate();
    }
  }

  @override
  void dispose() {
    _settings.autoChats.removeListener(_autoTranslate);
    _settings.targetLanguage.removeListener(_targetChanged);
    super.dispose();
  }

  void _targetChanged() {
    if (!mounted) return;
    MessageTranslator.instance.reset(_key);
    _autoTranslate();
  }

  void _autoTranslate() {
    if (!mounted || !_dependenciesReady || widget.isMe) return;
    if (!_settings.isAuto(widget.accountId, widget.chatId)) return;
    MessageTranslator.instance.translate(
      _key,
      widget.sourceText,
      target: translationTargetFor(context),
      auto: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MessageTranslationState>(
      valueListenable: MessageTranslator.instance.watch(_key),
      builder: (context, state, _) => widget.builder(
        state.sourceText == widget.sourceText &&
                state.targetLanguage == translationTargetFor(context)
            ? state
            : MessageTranslationState.idle,
      ),
    );
  }
}

class MessageTranslationFooter extends StatelessWidget {
  final String translationKey;
  final MessageTranslationState state;
  final Color color;
  final Color accent;

  const MessageTranslationFooter({
    super.key,
    required this.translationKey,
    required this.state,
    required this.color,
    required this.accent,
  });

  static bool hasContent(MessageTranslationState state) =>
      state.phase == TranslationPhase.loading ||
      state.phase == TranslationPhase.translated ||
      state.phase == TranslationPhase.original;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labelStyle = TextStyle(color: color, fontSize: 12);
    final linkStyle = TextStyle(
      color: accent,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final translator = MessageTranslator.instance;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: switch (state.phase) {
        TranslationPhase.loading => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SmallSpinner(size: 11, color: color),
            const SizedBox(width: 6),
            Text(l10n.translationTranslating, style: labelStyle),
          ],
        ),
        TranslationPhase.translated => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Icon(Symbols.translate, size: 13, color: color),
            Text(l10n.translationLabel, style: labelStyle),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => translator.showOriginal(translationKey),
              child: Text(l10n.msgActionsShowOriginal, style: linkStyle),
            ),
          ],
        ),
        TranslationPhase.original => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => translator.showTranslation(translationKey),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.translate, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(l10n.translationShowTranslation, style: linkStyle),
            ],
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
