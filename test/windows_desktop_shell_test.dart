import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/desktop/desktop_identity.dart';
import 'package:promax/core/desktop/desktop_window.dart';

void main() {
  final script = File('windows/installer/promax.iss').readAsStringSync();
  final runner = File('windows/runner/main.cpp').readAsStringSync();
  final window = File('windows/runner/flutter_window.cpp').readAsStringSync();

  test('the shortcuts, the process and the toasts share one AUMID', () {
    const aumid = DesktopIdentity.appUserModelId;
    expect(runner, contains('kAppUserModelId[] = L"$aumid"'));
    final shortcuts = script
        .split('\n')
        .where((line) => line.contains('Filename: "{app}\\ProMax.exe"'))
        .where((line) => line.startsWith('Name: "{auto'));
    expect(shortcuts, hasLength(2));
    for (final line in shortcuts) {
      expect(line, contains('AppUserModelID: "$aumid"'));
    }
  });

  test('autostart starts hidden with the argument the runner reads', () {
    const flag = DesktopWindow.minimizedArgument;
    expect(runner, contains('kMinimizedArgument[] = "$flag"'));
    expect(window, contains('L"\\" $flag"'));
    final run = script
        .split('\n')
        .singleWhere((line) => line.contains('Tasks: autostart'));
    expect(run, contains('CurrentVersion\\Run'));
    expect(run, contains('$flag"'));
    expect(run, contains('uninsdeletevalue'));
  });

  test('the runner serves the channels Dart calls', () {
    for (final channel in const [
      'io.github.stillemptynow.promax/window',
      'io.github.stillemptynow.promax/launcher_badge',
      'io.github.stillemptynow.promax/screen',
    ]) {
      expect(window, contains('"$channel"'));
    }
    for (final method in const [
      'presence',
      'reveal',
      'hide',
      'flash',
      'quit',
      'autostart',
      'setAutostart',
      'setCloseToTray',
      'setTrayLabels',
      'quitRequested',
    ]) {
      expect(window, contains('"$method"'));
    }
  });
}
