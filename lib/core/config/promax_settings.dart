import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_profile.dart';

// #***! фирменные настройки комета которых нет в оригинале
class ProMaxSettings {
  static const _kViewDeleted = 'promax_view_deleted';
  static const _kViewRedacted = 'promax_view_redacted';
  static const _kFullTimestamp = 'promax_full_timestamp';
  static const _kShowForward = 'promax_show_forward';
  static const _kShowTypingTime = 'promax_show_typing_time';
  static const _kGhostMode = 'promax_ghost_mode';
  static const _kAntiRead = 'promax_anti_read';
  static const _kSelfOnlineCheck = 'promax_self_online_check';
  static const _kHideAllChatsFolder = 'promax_hide_all_chats_folder';
  static const _kShowHiddenChats = 'promax_show_hidden_chats';
  static const _kArchiveOnPull = 'promax_archive_on_pull';
  static const _kRecordDebugLogs = 'promax_record_debug_logs';
  static const _kQuickReaction = 'promax_quick_reaction';
  static const _kNoTyping = 'promax_no_typing';
  static const _kHideStoryViews = 'promax_hide_story_views';
  static const _kStreamerMode = 'promax_streamer_mode';
  static const _kSwitcherBlur = 'promax_app_switcher_blur';

  // #***! каждая настройка это ValueNotifier, юишка подписана напрямую
  static final ValueNotifier<bool> viewDeleted = ValueNotifier(false);
  static final ValueNotifier<bool> viewRedacted = ValueNotifier(false);
  static final ValueNotifier<bool> fullTimestamp = ValueNotifier(false);
  static final ValueNotifier<bool> showForward = ValueNotifier(false);
  static final ValueNotifier<bool> showTypingTime = ValueNotifier(false);
  static final ValueNotifier<bool> ghostMode = ValueNotifier(false);
  static final ValueNotifier<bool> streamerMode = ValueNotifier(false);
  static final ValueNotifier<bool> switcherBlur = ValueNotifier(false);
  static final ValueNotifier<bool> antiRead = ValueNotifier(false);
  static final ValueNotifier<bool> selfOnlineCheck = ValueNotifier(true);
  static final ValueNotifier<bool> hideAllChatsFolder = ValueNotifier(false);
  static final ValueNotifier<bool> showHiddenChats = ValueNotifier(false);
  static final ValueNotifier<bool> archiveOnPull = ValueNotifier(false);
  static final ValueNotifier<bool> recordDebugLogs = ValueNotifier(false);
  static final ValueNotifier<String> quickReaction = ValueNotifier('❤️');
  static final ValueNotifier<bool> noTyping = ValueNotifier(false);
  static final ValueNotifier<bool> hideStoryViews = ValueNotifier(false);

  // #***! читаем всё разом на старте
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // #***! просмотр удалённого только вне store сборки
    viewDeleted.value =
        BuildProfile.hiddenContentViewers &&
        (prefs.getBool(_kViewDeleted) ?? false);
    viewRedacted.value =
        BuildProfile.hiddenContentViewers &&
        (prefs.getBool(_kViewRedacted) ?? false);
    fullTimestamp.value = prefs.getBool(_kFullTimestamp) ?? false;
    showForward.value = prefs.getBool(_kShowForward) ?? false;
    showTypingTime.value = prefs.getBool(_kShowTypingTime) ?? false;
    ghostMode.value = prefs.getBool(_kGhostMode) ?? false;
    antiRead.value = prefs.getBool(_kAntiRead) ?? false;
    quickReaction.value = prefs.getString(_kQuickReaction) ?? '❤️';
    noTyping.value = prefs.getBool(_kNoTyping) ?? false;
    hideStoryViews.value = prefs.getBool(_kHideStoryViews) ?? false;
    streamerMode.value = prefs.getBool(_kStreamerMode) ?? false;
    switcherBlur.value = prefs.getBool(_kSwitcherBlur) ?? false;
    selfOnlineCheck.value = prefs.getBool(_kSelfOnlineCheck) ?? true;
    hideAllChatsFolder.value = prefs.getBool(_kHideAllChatsFolder) ?? false;
    showHiddenChats.value = prefs.getBool(_kShowHiddenChats) ?? false;
    archiveOnPull.value = prefs.getBool(_kArchiveOnPull) ?? false;
    recordDebugLogs.value = prefs.getBool(_kRecordDebugLogs) ?? false;
  }

  // #***! дальше по сеттеру на настройку, память потом диск
  static Future<void> setStreamerMode(bool value) async {
    streamerMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStreamerMode, value);
  }

  static Future<void> setSwitcherBlur(bool value) async {
    switcherBlur.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSwitcherBlur, value);
  }

  static Future<void> setViewDeleted(bool value) async {
    viewDeleted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kViewDeleted, value);
  }

  static Future<void> setViewRedacted(bool value) async {
    viewRedacted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kViewRedacted, value);
  }

  static Future<void> setFullTimestamp(bool value) async {
    fullTimestamp.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFullTimestamp, value);
  }

  static Future<void> setShowForward(bool value) async {
    showForward.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowForward, value);
  }

  static Future<void> setShowTypingTime(bool value) async {
    showTypingTime.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowTypingTime, value);
  }

  // #***! невидимка влияет на пинг, с interactive false сервер не считает нас онлайн
  static Future<void> setGhostMode(bool value) async {
    ghostMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGhostMode, value);
  }

  static Future<void> setAntiRead(bool value) async {
    antiRead.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAntiRead, value);
  }

  static Future<void> setQuickReaction(String value) async {
    if (value.trim().isEmpty) return;
    quickReaction.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQuickReaction, value);
  }

  static Future<void> setNoTyping(bool value) async {
    noTyping.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNoTyping, value);
  }

  static Future<void> setHideStoryViews(bool value) async {
    hideStoryViews.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideStoryViews, value);
  }

  static Future<void> setSelfOnlineCheck(bool value) async {
    selfOnlineCheck.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSelfOnlineCheck, value);
  }

  static Future<void> setHideAllChatsFolder(bool value) async {
    hideAllChatsFolder.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideAllChatsFolder, value);
  }

  static Future<void> setArchiveOnPull(bool value) async {
    archiveOnPull.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kArchiveOnPull, value);
  }

  static Future<void> setShowHiddenChats(bool value) async {
    showHiddenChats.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowHiddenChats, value);
  }

  static Future<void> setRecordDebugLogs(bool value) async {
    recordDebugLogs.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRecordDebugLogs, value);
  }
}
