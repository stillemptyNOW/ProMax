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

## Built-in native plugins (Motion Blur)

Besides the JS command plugins (`PluginStore`, `.pmx`), ProMax ships native built-ins that can draw
UI: `NativePlugin` / `NativePlugins` in `lib/core/plugins/native_plugin.dart`, listed on the Plugins
screen through `nativePluginEntries` (`frontend/screens/profile/native_plugin_entries.dart`, title,
icon and settings screen). They are not downloaded code, so the Plugins screen stays in App Store
builds with only the native section. The first one is Motion Blur (`core/plugins/motion_blur/`,
`frontend/widgets/motion_blur/`, `shaders/motion_blur.frag`), installed but off by default, settings
persisted as JSON under `native_plugin_motion_blur_v1`.

`MotionBlurBox` hosts the blur: at rest it paints its child directly (no filter layer); while
something moves it pushes a clip plus an `ImageFilterLayer` with `ImageFilter.shader` (directional
taps along the velocity), or a single-axis `ImageFilter.blur` where shader filters are unavailable.
It is wired in once per target: every scrollable through `MotionBlurScrollBehavior` (installed on
`MaterialApp`; its `copyWith` keeps the wrapper, and custom behaviors are passed in as `inner`), page
routes through `MotionBlurPageTransitionsBuilder` and `SwipeRoute`, the main tabs in
`chat_list_screen.dart`, the pill-nav lens in `sliding_pill_nav.dart`. Reduce motion disables it.

A layer filter cannot reach platform views (iOS 26 native glass, the native `UITabBar`, the mini-app
WebView), so every `UiKitView`/WebView is wrapped in `MotionBlurExclusion`: while one is mounted, all
`MotionBlurBox` ancestors stay unfiltered. Wrap any new platform view the same way.

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

The catalogue is `AppIcon` in `lib/core/config/app_icon_catalog.dart`: the primary icon, the
mark variants `Light`, `Aurora`, `Sunset`, `Glass` (from `design/promax-logo-source.png`) and the
seasonal artworks `Halloween`, `NewYear` (full square artworks `design/promax-logo-{halloween,newyear}.png`,
cropped around the `center`/`extent` set in the generator). `python tool/make_promax_icons.py`
(Pillow) writes everything: the transparent mark `assets/promax.png`, the flattened
`assets/promax_icon.png`, previews in `assets/icons/`, `ios/Runner/Icon<Name>@{2,3}x.png` plus their
`CFBundleAlternateIcons` entries in `Info.plist` and file references in `project.pbxproj`, Android
`mipmap-*/ic_launcher_<name>.png` (legacy), `mipmap-anydpi-v26/ic_launcher_<name>.xml` (adaptive:
gradient background + mark foreground for the variants, the artwork as background with its subject
inside the 66dp safe zone for the seasonal ones, the shared monochrome layer), Windows
`windows/runner/resources/app_icon_<name>.ico`, the primary `AppIcon.appiconset` and the Inno Setup
wizard images `windows/installer/wizard_{image,small}_{100,150,200}.png` (`--installer-only`
regenerates just those). Re-running it rewrites existing PNGs byte-for-byte differently but with
identical pixels; restore those with `git checkout` instead of committing the churn.

`AppIconConfig` (`lib/core/config/app_icon.dart`) switches icons through the
`io.github.stillemptynow.promax/app_icon` channel on every platform but web:
- Android: `MainActivity` has no visible launcher entry (its MAIN/LAUNCHER filter carries a
  `promax-direct-launch` data scheme only so `flutter run` still finds a launchable activity). Each
  icon is an `activity-alias` `Icon<Name>` with the LAUNCHER filter; `IconDefault` is enabled in
  the manifest, the rest are disabled. `MainActivity.applyIcon` enables the target alias first and
  then disables the others (`DONT_KILL_APP`), `getAppIcon` reports the enabled alias. Launchers drop
  chat shortcuts and may need the icon re-added to the home screen, so a manual switch asks first and
  closes the app; the seasonal switch waits until the app goes to the background and never closes it.
- iOS: `setAlternateIconName` with `Icon<Name>` (nil for the primary).
- Windows: `WM_SETICON` (DPI-sized, also the tray icon) from `IDI_ICON_*` resources in `Runner.rc`.
  macOS: `NSApplication.applicationIconImage` (dock icon, drawn on the 824/1024 grid). Linux:
  `gtk_window_set_icon`. Dart sends the preview PNG to macOS and Linux. Desktop icons reset on every
  launch, so the stored choice is re-applied at startup; installed shortcuts keep the primary icon.

The seasonal auto-switch (off by default) shows Halloween from Oct 24 to Nov 2 and New Year from
Dec 20 to Jan 10, checked at start and on resume. The user's own choice (`app_icon`) is stored apart
from the season state; a manual pick during a season is kept until that season ends
(`app_icon_manual_season`). `app_icon_auto_applied` remembers an icon the season put on so it can be
removed, and `app_icon_auto_attempt` limits Android to one automatic attempt per target per day.
`test/app_icon_names_test.dart` checks the catalogue against every platform's assets, the manifest,
`MainActivity`, `Info.plist`, `project.pbxproj` and the Windows resources.

## Localization

Two locales supported: English (`lib/l10n/app_en.arb`) and Russian (`lib/l10n/app_ru.arb`).  
Generated code is in `lib/l10n/` (produced by `flutter gen-l10n` via `l10n.yaml`).

## CI/CD

`.github/workflows/promax-ios.yml` verifies the app and builds an unsigned iOS IPA.
`.github/workflows/promax-platforms.yml` builds split-per-ABI and universal `promax` APKs,
the Windows bundle with the Visual C++ runtime copied next to `ProMax.exe`, the per-user
Inno Setup installer from `windows/installer/promax.iss` (`ProMax-Setup-<version>-<build>.exe`)
and the Linux bundle. Pushing a `v*` tag publishes everything — IPA, `.pmx`
tools package, APKs, desktop archives — into one public GitHub Release through
`.github/scripts/publish-release.sh`. APKs are named `ProMax-<version>-promax-<abi>.apk`
because the in-app updater picks them by the `-promax-<abi>.apk` suffix. Without the
`ANDROID_KEYSTORE_*` secrets each build is signed with a throwaway debug key, so those APKs are
published as `ProMax-<version>-preview-<abi>.apk`: the updater never installs them over an existing
copy, and moving between preview builds needs a reinstall. The in-app updater reads
the 20 most recent releases of the public ProMax repository and takes the newest by the version and
build in the tag (`newestRelease`), because GitHub's list order does not follow them. It verifies
downloaded files by their published size and SHA-256 digest. iOS sends the IPA to the share sheet so
the user can import it into eSign; iOS does not let this app silently replace itself.

The Windows job compiles the installer with the runner's Inno Setup when it is 6.5.2 or newer (the
first with PNG wizard images), otherwise with `choco upgrade innosetup`. On Windows the updater
installs in-app only when ProMax runs from an installed copy (`unins000.exe` next to `ProMax.exe`)
and the release has a `ProMax-Setup-*.exe` with a published digest; the portable zip, Linux and macOS
open the release page instead. It runs the setup detached with
`/SILENT /SUPPRESSMSGBOXES /NORESTART /LOG /relaunch=1` and quits. `CloseApplications=force` lets
Restart Manager close a ProMax that is still exiting, and the silent-only `[Run]` entry guarded by
`RelaunchRequested` (`/relaunch=1`) starts ProMax again as the original user. Keep
`UpdateInstaller.windowsSetupArguments`, the `ProMax-Setup-` prefix and `promax.iss` in sync;
`test/update_windows_installer_test.dart` checks them.
