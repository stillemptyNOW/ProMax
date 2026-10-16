import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RegGetValueNative =
    Int32 Function(
      IntPtr key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> value,
      Uint32 flags,
      Pointer<Uint32> type,
      Pointer<Void> data,
      Pointer<Uint32> size,
    );
typedef _RegGetValueDart =
    int Function(
      int key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> value,
      int flags,
      Pointer<Uint32> type,
      Pointer<Void> data,
      Pointer<Uint32> size,
    );
typedef _RegSetKeyValueNative =
    Int32 Function(
      IntPtr key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> valueName,
      Uint32 type,
      Pointer<Void> data,
      Uint32 size,
    );
typedef _RegSetKeyValueDart =
    int Function(
      int key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> valueName,
      int type,
      Pointer<Void> data,
      int size,
    );

class WindowsRegistry {
  WindowsRegistry._(DynamicLibrary advapi)
    : _getValue = advapi.lookupFunction<_RegGetValueNative, _RegGetValueDart>(
        'RegGetValueW',
      ),
      _setKeyValue = advapi
          .lookupFunction<_RegSetKeyValueNative, _RegSetKeyValueDart>(
            'RegSetKeyValueW',
          );

  static const int _currentUser = -0x7FFFFFFF;
  static const int _success = 0;
  static const int _regSz = 1;
  static const int _regDword = 4;
  static const int _restrictSz = 0x00000002;
  static const int _restrictDword = 0x00000010;

  static WindowsRegistry? _instance;

  static WindowsRegistry? get currentUser {
    if (!Platform.isWindows) return null;
    try {
      return _instance ??= WindowsRegistry._(
        DynamicLibrary.open('advapi32.dll'),
      );
    } catch (_) {
      return null;
    }
  }

  final _RegGetValueDart _getValue;
  final _RegSetKeyValueDart _setKeyValue;

  String? readString(String subKey, String? valueName) => using((arena) {
    final key = subKey.toNativeUtf16(allocator: arena);
    final name = valueName?.toNativeUtf16(allocator: arena) ?? nullptr;
    final size = arena<Uint32>();
    var status = _getValue(
      _currentUser,
      key,
      name,
      _restrictSz,
      nullptr,
      nullptr,
      size,
    );
    if (status != _success || size.value == 0) return null;
    final data = arena<Uint8>(size.value + 2);
    status = _getValue(
      _currentUser,
      key,
      name,
      _restrictSz,
      nullptr,
      data.cast(),
      size,
    );
    if (status != _success) return null;
    return data.cast<Utf16>().toDartString();
  });

  bool writeString(String subKey, String? valueName, String value) =>
      using((arena) {
        final data = value.toNativeUtf16(allocator: arena);
        return _setKeyValue(
              _currentUser,
              subKey.toNativeUtf16(allocator: arena),
              valueName?.toNativeUtf16(allocator: arena) ?? nullptr,
              _regSz,
              data.cast(),
              (value.length + 1) * 2,
            ) ==
            _success;
      });

  int? readDword(String subKey, String valueName) => using((arena) {
    final data = arena<Uint32>();
    final size = arena<Uint32>()..value = 4;
    final status = _getValue(
      _currentUser,
      subKey.toNativeUtf16(allocator: arena),
      valueName.toNativeUtf16(allocator: arena),
      _restrictDword,
      nullptr,
      data.cast(),
      size,
    );
    return status == _success ? data.value : null;
  });

  bool writeDword(String subKey, String valueName, int value) => using((arena) {
    final data = arena<Uint32>()..value = value;
    return _setKeyValue(
          _currentUser,
          subKey.toNativeUtf16(allocator: arena),
          valueName.toNativeUtf16(allocator: arena),
          _regDword,
          data.cast(),
          4,
        ) ==
        _success;
  });
}
