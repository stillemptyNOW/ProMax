import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/utils/user_facing_error.dart';

void main() {
  test('server errors keep their own text', () {
    expect(
      userFacingError(const PacketError('Сообщение слишком длинное')),
      'Сообщение слишком длинное',
    );
    expect(userFacingError(const PacketError('  ')), 'Неизвестная ошибка');
  });

  test('timeouts and lost connections become plain words', () {
    expect(
      userFacingError(TimeoutException('MSG_SEND таймаут')),
      'Сервер не ответил',
    );
    expect(
      userFacingError(StateError('Нет соединения (MSG_SEND)')),
      'Нет соединения',
    );
    expect(
      userFacingError(StateError('Сессия изменилась до отправки')),
      'Нет соединения',
    );
    expect(
      userFacingError(const SocketException('Connection refused')),
      'Нет соединения',
    );
  });

  test('readable state errors pass through, internal ones do not', () {
    expect(
      userFacingError(StateError('Встроенный плагин нельзя удалить')),
      'Встроенный плагин нельзя удалить',
    );
    expect(
      userFacingError(StateError('Bad state: null')),
      'Неизвестная ошибка',
    );
    expect(
      userFacingError(Exception('initiateCall: bad response')),
      'Неизвестная ошибка',
    );
    expect(userFacingError(const FormatException('x')), 'Неизвестная ошибка');
    expect(
      userFacingError(const FormatException('Файл слишком большой')),
      'Файл слишком большой',
    );
  });
}
