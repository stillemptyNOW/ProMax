import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../push/push_service.dart';
import '../utils/logger.dart';
import 'message_reminders.dart';

const _payloadType = 'reminder';

String reminderPayload(MessageReminder reminder) => jsonEncode({
  'type': _payloadType,
  'chat': reminder.chatId,
  'mid': reminder.messageId,
});

int? reminderChatFromPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map || decoded['type'] != _payloadType) return null;
    final chat = decoded['chat'];
    return chat is int ? chat : null;
  } catch (_) {
    return null;
  }
}

String reminderTitle(MessageReminder reminder) => reminder.chatName.isEmpty
    ? 'Напоминание'
    : 'Напоминание · ${reminder.chatName}';

ReminderScheduler? platformReminderScheduler({
  required void Function(int chatId) openChat,
}) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => _AndroidReminderScheduler(openChat),
    TargetPlatform.iOS => _IosReminderScheduler(),
    _ => null,
  };
}

class _AndroidReminderScheduler implements ReminderScheduler {
  _AndroidReminderScheduler(this._openChat) {
    addLocalNotificationTapHandler(_onTap);
    _openLaunchReminder();
  }

  static const _channelId = 'promax_reminders';
  static const _channelName = 'Напоминания';

  final void Function(int chatId) _openChat;
  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  bool _onTap(String payload) {
    final chat = reminderChatFromPayload(payload);
    if (chat == null) return false;
    _openChat(chat);
    return true;
  }

  Future<void> _openLaunchReminder() async {
    try {
      await initLocalNotificationActions();
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true && payload != null) {
        _onTap(payload);
      }
    } catch (e) {
      logger.w('Reminders: launch details unavailable: $e');
    }
  }

  @override
  Future<bool> ensurePermission() async {
    await initLocalNotificationActions();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> schedule(MessageReminder reminder) async {
    await initLocalNotificationActions();
    try {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminderTitle(reminder),
        body: reminder.preview,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.UTC,
          reminder.at,
        ),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(reminder.preview),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminderPayload(reminder),
      );
    } catch (e) {
      logger.w('Reminders: schedule failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      logger.w('Reminders: cancel failed: $e');
    }
  }
}

class _IosReminderScheduler implements ReminderScheduler {
  static const _method = MethodChannel(
    'io.github.stillemptynow.promax/notifications',
  );

  @override
  Future<bool> ensurePermission() async {
    try {
      return await _method.invokeMethod<bool>('requestReminderPermission') ??
          false;
    } catch (e) {
      logger.w('Reminders: permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> schedule(MessageReminder reminder) async {
    try {
      await _method.invokeMethod<void>('scheduleReminder', {
        'id': '${reminder.id}',
        'chatId': reminder.chatId,
        'title': reminderTitle(reminder),
        'body': reminder.preview,
        'at': reminder.at,
      });
    } catch (e) {
      logger.w('Reminders: schedule failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _method.invokeMethod<void>('cancelReminder', {'id': '$id'});
    } catch (e) {
      logger.w('Reminders: cancel failed: $e');
    }
  }
}
