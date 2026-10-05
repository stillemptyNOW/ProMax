# promax_crypto (Flutter)

`dart:ffi` bindings for the C core in the repository root. The native library is
compiled from `../../CMakeLists.txt` (Android, Linux, Windows) or from the
forwarder files in `ios/Classes` and `macos/Classes` (CocoaPods). On the web
every call throws `ProMaxCryptoException(CryptoStatus.unavailable)`.

Add to an app:

```yaml
promax_crypto:
  git:
    url: https://github.com/stillemptyNOW/ProMax
    path: flutter/promax_crypto
    ref: <commit>
```

Tests run against the host build of the core: `make shared` in the repository
root, then `flutter test` here.
