import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import '../../l10n/app_localizations.dart';
import '../protocol/packet.dart';

const _connectionLossPrefixes = ['Нет соединения', 'Сессия изменилась'];
final _readableText = RegExp('[А-Яа-яЁё]');

AppLocalizations appLocalizationsFallback() =>
    lookupAppLocalizations(const Locale('ru'));

bool isConnectionLoss(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    (error is StateError &&
        _connectionLossPrefixes.any(error.message.startsWith));

String userFacingError(Object error, [AppLocalizations? l10n]) {
  final strings = l10n ?? appLocalizationsFallback();
  if (error is PacketError) {
    final message = error.message.trim();
    return message.isEmpty ? strings.errorUnknown : message;
  }
  if (error is TimeoutException) return strings.errorServerNoResponse;
  if (isConnectionLoss(error)) return strings.errorNoConnection;
  final readable = switch (error) {
    StateError(:final message) => message,
    FormatException(:final message) => message,
    HttpException(:final message) => message,
    _ => null,
  };
  if (readable != null && _readableText.hasMatch(readable)) return readable;
  if (error is FileSystemException) {
    final reason = error.osError?.message.trim() ?? '';
    return reason.isNotEmpty ? reason : strings.errorFileAccess;
  }
  return strings.errorUnknown;
}
