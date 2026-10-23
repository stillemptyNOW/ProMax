import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/call_controller.dart';

bool _system({
  bool resumed = false,
  bool visible = true,
  bool desktop = false,
  bool backgroundNotifications = false,
  bool firebasePush = false,
}) => CallController.systemShowsIncoming(
  resumed: resumed,
  visible: visible,
  desktop: desktop,
  backgroundNotifications: backgroundNotifications,
  firebasePush: firebasePush,
);

void main() {
  test('a resumed app rings in the app', () {
    expect(_system(resumed: true, backgroundNotifications: true), isFalse);
  });

  test('desktop always rings in the app', () {
    expect(_system(desktop: true, visible: false), isFalse);
  });

  test('a visible but inactive app rings in the app without a system path', () {
    expect(_system(), isFalse);
  });

  test('background notifications take the call over when not resumed', () {
    expect(_system(backgroundNotifications: true), isTrue);
    expect(_system(firebasePush: true), isTrue);
  });

  test('a hidden app leaves the call to the system', () {
    expect(_system(visible: false), isTrue);
  });
}
