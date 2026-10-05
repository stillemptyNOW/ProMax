# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ProMax is a cross-platform Flutter messaging client (Android, iOS, macOS, Windows, Linux, Web) that communicates via a custom packet-based protocol with MessagePack serialization and Zstd compression.

## Commands

```bash
flutter pub get          # install dependencies
flutter analyze lib test tool  # lint / static analysis (what CI runs)
flutter run              # run on connected device (default: promax flavor)
flutter run --flavor oneme -t lib/main.dart  # run oneme flavor (FCM)

# Android builds (release builds use obfuscation; keep symbols to de-obfuscate crashes)
flutter build apk --release --flavor promax --obfuscate --split-debug-info=build/symbols
flutter build apk --release --split-per-abi --flavor promax --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --flavor promax --obfuscate --split-debug-info=build/symbols

# Other platforms
flutter build ios --release --no-codesign
flutter build macos --release
flutter build web --release
flutter build linux --release
flutter build windows --release
```

Android builds require **Java 17**. Gradle memory is configured to `-Xmx4096m`.

**Never run APK/AAB builds yourself** (`flutter build apk`, `flutter build appbundle`, gradle assemble tasks) — they are slow and the user builds them. Verify changes with the scoped `flutter analyze` above; the build commands are documentation only.
Note that `flutter analyze` treats **info**-level lints as fatal by default, so CI fails on any lint.

## Message encryption core

`promax_crypto` is a `dart:ffi` plugin over the C core vendored in `native/promax_crypto`
(no submodule). The plugin lives in `native/promax_crypto/flutter/promax_crypto` and compiles
the core sources directly. Protocol and byte formats are specified in
`native/promax_crypto/docs/PROTOCOL.md` — never reimplement them in Dart. The core's own suite
(`make -C native/promax_crypto test`, `make asan`) must pass after every change to it; CI runs it.

## Sticker renderer

Animated stickers, animoji and reactions are rendered by [tlottie](https://github.com/dkaraush/tlottie)
(Rust) through the local FFI plugin `native/promax_tlottie`. Its wrapper crate pins tlottie by an
exact git `rev`, and the vendored cargokit compiles it during the Flutter build with the same
toolchain as `kolibri`; bump it by changing the `rev` and running `cargo update -p tlottie`.
`lib/core/media/tlottie/` renders frames in a pool of worker isolates and caches them in RAM and
on disk. Web has no native path and falls back to the pure-Dart `lottie` package.

## Build Flavors

| Flavor  | App ID         | Notes                               |
|---------|----------------|-------------------------------------|
| `promax` | `io.github.stillemptynow.promax` | Default, no FCM                     |
| `oneme` | `ru.oneme.app` | FCM push notifications via Firebase |
| `store` | `io.github.stillemptynow.promax.play` | Google Play build, trimmed by `BuildProfile` |

Flavor-specific Android resources live in `android/app/src/promax/`, `android/app/src/oneme/`
and `android/app/src/store/`.

The store build carries its own application id — `io.github.stillemptynow.promax.play`, the same identifier as the iOS
bundle — because `io.github.stillemptynow.promax` has already shipped outside Play. The Kotlin sources keep the
`io.github.stillemptynow.promax` namespace: component names in the manifest are absolute, and `MainActivity` derives
the launcher-alias package from its own class name, so the icon switch survives the rename.
`android/app/src/store/google-services.json` must repeat the same id or the Google Services plugin
fails the build.

## Architecture

The codebase follows a strict layered architecture:

```
core/transport/    — raw socket I/O: connection, sender, receiver, dispatcher, proxy
core/protocol/     — Packet struct, opcode map, MessagePack + Zstd serialization
core/storage/      — SQLite (sqflite), secure token storage, spoofing service
core/push/         — FCM integration (oneme flavor only)
core/config/       — app config, proxy config, device presets, countries list

backend/api.dart   — session lifecycle: connect, handshake, ping, auto-reconnect
backend/modules/   — feature modules: account, messages, chats, contacts, calls, folders

models/            — plain data classes (User, Chat, Message, Call, Attachment, Session)

frontend/screens/  — full-page widgets grouped by feature (auth/, chats/, contacts/, calls/, profile/)
frontend/widgets/  — reusable components (message_bubble, chat_tile, avatar, etc.)
```

Data flow: UI → backend module → `api.dart` → transport layer → server.  
Incoming packets: transport → dispatcher → backend module → state → UI rebuild.

State is `ChangeNotifier`-based but not centralized in one directory: it lives next to the
feature it belongs to — e.g. `ChatListState` in `frontend/screens/chats/chat_list_screen.dart`,
`ChatController` in `frontend/screens/chats/chat/chat_controller.dart`, `PollsState` in
`backend/modules/polls.dart`. Colocate new state with its screen/module rather than adding a
top-level `state/` directory.

Wire framing, MessagePack, and Zstd (de)compression are handled by the `kolibri` Rust package
from pub.dev — `core/protocol/packet.dart` only wraps the already-decoded payload. There is no serialization work to move off the Dart isolate here; it never runs on it.

## Key Conventions (see [AGENTS.md](./AGENTS.md) for the full, canonical list)

- **No comments in code.** Write self-documenting code instead.
- **Use `showCustomNotification(context, 'text')`** for all user-facing notifications — never use SnackBars.
- **Feedback about one specific on-screen element goes through `showHintBubble(anchorContext, 'text')`** (`lib/frontend/widgets/hint_bubble.dart`) — an anchored bubble next to that element instead of the bottom notification. Pass the element's own context, not the screen's.
- When a fix can be done quickly with a hack or properly with a rewrite, **choose the proper rewrite**.
- Quality over quantity.
- **Never leave real data in test files**, including existing message contents or real IDs captured from requests. Use synthetic fixtures instead.
- **A button whose icon toggles between plain and slashed** (flash on/off, mic muted, sound, notifications) **must animate with a Lottie icon** — never swap two `Icon`s instantly. See *Animated icons* below.
- **Never `git commit` unless explicitly asked**, even for trivial changes — leave them in the working tree or stash instead.

## Flutter performance conventions

These are established patterns already in use in this codebase — follow them for new code
rather than introducing a different approach.

- **Heavy CPU work goes through `compute()`, not the main isolate.** `core/utils/image_utils.dart`
  and `core/media/image_optimizer.dart` already offload JPEG/AVIF encoding this way
  (`compute(_encodeAvatarFile, ...)`, `compute(_encodePhotoIsolate, ...)`). Follow the same
  pattern for any new CPU-bound Dart work (image/video processing, large data transforms).
  Note this does **not** apply to wire (de)serialization — MessagePack/Zstd is handled by the
  Rust core (`kolibri`), not Dart, so there's nothing to offload there.
- **`ListView.builder` + `ValueKey` is the norm for lists** (chat list, message list, contacts,
  attachments) — the codebase already uses this pattern in ~40 files. Keep using `ValueKey` on
  list items whose identity matters across rebuilds (reorder, delete, optimistic updates),
  otherwise Flutter can misattribute state to the wrong item.
- **Dispose what you subscribe.** `ChangeNotifier`-based controllers/state classes are colocated
  with their screen or module (see *Architecture* above, not a shared `state/` tree) — each one
  must cancel its `StreamSubscription`s and dispose its controllers (`AnimationController`,
  `TextEditingController`, etc.) in its own `dispose()`.
- **Prefer `const` constructors** wherever the widget's properties are compile-time constant —
  it lets Flutter skip rebuilding that subtree entirely.
- **Keep `build()` pure and cheap** — no network/IO calls, no heavy computation inline; extract
  reusable pieces into their own `StatelessWidget`s instead of nesting logic in one big builder.

## Animated icons

Everything in `assets/lottie/` is generated from the Material Symbols font by `tool/make_morph_icons.py` (stdlib-only Python, no deps). Never hand-edit the JSON — add a spec and re-run `python3 tool/make_morph_icons.py`.

| Kind                     | Spec list     | Widget              |
|--------------------------|---------------|---------------------|
| Morph between two glyphs | `SPECS`       | `ComposerMorphIcon` |
| Plain ↔ slashed toggle   | `SLASH_SPECS` | `LottieSlashIcon`   |

A slash spec takes the plain and slashed codepoints; the generator lays both glyphs out as static layers and sweeps a mask across the diagonal, so the slash looks drawn on top of the icon. Pass `fill=1.0` when the button renders `Icon(..., fill: 1)` — contours are then taken from the `FILL=1` instance of the variable font.

`LottieSlashIcon` plays the asset forward when `slashed` turns true and backward when it turns false, so a single asset covers both directions. The older `AnimatedSlashIcon` (clip wipe over two glyphs) stays where it is already used; new buttons use the Lottie one.

## App icons

The primary icon and four iOS alternate icons (`Light`, `Aurora`, `Sunset`, `Glass`) are all
generated by `python tool/make_promax_icons.py` from `design/promax-logo-source.png`. It writes
the transparent mark `assets/promax.png`, the flattened `assets/promax_icon.png`, previews in
`assets/icons/`, `ios/Runner/Icon<Name>@{2,3}x.png` and the primary `AppIcon.appiconset`.
`AppIconConfig` switches them at runtime; Android only ships the primary icon.

## Localization

Two locales supported: English (`lib/l10n/app_en.arb`) and Russian (`lib/l10n/app_ru.arb`).  
Generated code is in `lib/l10n/` (produced by `flutter gen-l10n` via `l10n.yaml`).

## CI/CD

`.github/workflows/promax-ios.yml` verifies the app and builds an unsigned iOS IPA.
Pushing a `v*` tag also publishes the IPA and `.pmx` tools package as a public
GitHub Release. The in-app updater reads the latest release metadata from the
public ProMax repository and verifies downloaded files by their published size
and SHA-256 digest. iOS sends the IPA to the share sheet so the user can import it
into eSign; iOS does not let this app silently replace itself.
