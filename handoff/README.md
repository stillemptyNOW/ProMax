# ProMax beta 12 — handoff

Unfinished work for ProMax 1.1.0 beta 12, stopped mid-way. Each `b12-*.mbox` is a `git format-patch --binary`
series (the last commit of each is an uncommitted-work snapshot named `WIP b12-<area> (handoff)`).
Base commits: perf, cleanup, notif, icons → `0067e96`; ml, pip, misc → `2a30aa0`. All apply on top of the
branch `claude/confident-bohr-2dd5e7` (which contains both bases).

## Prompt for the next AI

You continue development of ProMax, a Flutter client for the Russian messenger MAX
(repo `stillemptyNOW/ProMax`, work branch `claude/confident-bohr-2dd5e7`). Read `CLAUDE.md` and `AGENTS.md` first and
follow them: no comments in code, `showCustomNotification` / `showHintBubble` instead of SnackBars, proper
rewrites instead of hacks, synthetic data only in tests, Lottie for slash-toggle icons, colocated
`ChangeNotifier` state, dispose what you subscribe. User-facing strings in Russian (+ English in `app_en.arb`,
then `flutter gen-l10n`). Never run APK/AAB builds locally; CI builds them. Verify with
`flutter analyze lib test tool native/promax_effects/lib` (must print "No issues found!", info lints are fatal)
and the full `flutter test` suite. Native code (Kotlin, Swift, Obj-C++, C++) usually cannot be compiled locally:
write it carefully against real APIs; CI (`.github/workflows/promax-ios.yml`, `promax-platforms.yml`) compiles it.
The owner talks in Russian, wants short answers, and authorises commits/PRs/releases on this repo.

Work items (one branch each; apply the patch series with `git checkout -b b12-<area> claude/confident-bohr-2dd5e7 &&
git am -3 handoff/b12-<area>.mbox`, finish the work, run analyze + tests, squash or keep logical commits):

1. **b12-perf** — ProMax lags badly on Android. Find real causes (glass shader/BackdropFilter count per screen
   after beta 11 made toasts/menus/dialogs/headers glass, per-frame trackers, Motion Blur wrappers, the
   «Атмосфера» effect, rebuild storms in chat list / message list, full-size image decodes, startup work on the
   UI isolate) and fix them; add a device-tier detector that downgrades effects on weak Android devices and a
   «Производительность» setting (Авто / Максимум плавности / Максимум красоты). Move «Атмосфера» so it renders
   only behind the messages inside a chat (never on the main screen) and optimise it. Make the blur option of the
   switch («размытие в переключателе») available on all OSes. State when stopped: implementation largely done,
   it was writing tests.
2. **b12-cleanup** — remove features that don't work, as real removals: the client-side ignore list «Запрет
   писать мне», every «удалить у всех / у обоих» option and the wipe-for-both tool (keep delete-for-me), streamer
   mode, adding fonts by URL (keep adding by file), plus other verified non-working/placebo features (list them
   with evidence). Was auditing the last candidates.
3. **b12-notif** — bug: in «не читать» (anti-read) mode a single new message shows ALL older messages in the
   notification. Beta 10's local read watermark didn't fix it. Root-cause end to end on Android (native
   `ChatNotifications.kt` / `ProMaxFcmService.kt` MessagingStyle history, headless engine) and iOS
   (`ProMaxLiveConnection.swift`, `ProMaxNotifications.swift`), fix, with tests that fail before the fix. Was
   verifying the new tests fail without the fix.
4. **b12-icons** — app icon switchable on every platform (iOS alternate icons, Android launcher activity-aliases
   for every icon, Windows/Linux/macOS runtime window/dock icon), new icons «Хэллоуин» and «Новый год» from
   `design/promax-logo-halloween.png` and `design/promax-logo-newyear.png` via `tool/make_promax_icons.py`, and a
   «Сезонная иконка автоматически» switch (Halloween Oct 24–Nov 2, New Year Dec 20–Jan 10, back to the user's
   choice afterwards; on Android switch only when the app goes to background). NO custom user-uploaded icon (the
   owner cancelled it). Was running the test suite.
5. **b12-ml** — on-device message translation (long-press «Перевести», «Переводить чат»; Android ML Kit
   translate + language-id, iOS Translation framework via a hidden SwiftUI `.translationTask` host, iOS 18+) and
   «Сделать стикер» from a photo (iOS 17+ Vision foreground mask, Android ML Kit subject segmentation; transparent
   ≤512 px with white outline, sent through the existing image/sticker path). Was writing settings/cache/translator.
6. **b12-pip** — picture-in-picture for video calls (Android PiP params + auto-enter + RemoteActions + minimal
   Flutter PiP layout; iOS 15+ AVPictureInPictureVideoCallViewController fed by an AVSampleBufferDisplayLayer from
   remote RTCVideoFrames), setting «Картинка в картинке в видеозвонках». Was writing the Dart core.
7. **b12-misc** — quick reply templates in the composer (settings to manage, non-conflicting trigger, insert at
   cursor), in-app updater shows «Что нового» (rendered release notes of all newer releases), and CI publishes
   only signed `ProMax-<v>-promax-<abi>.apk`, deleting stale `-preview-` APKs from the release. Was fixing test
   localizations.

Then merge all seven into `claude/confident-bohr-2dd5e7` (resolve conflicts keeping both sides), run analyze and the
full suite, push, run trial CI builds (`promax-ios.yml` and `promax-platforms.yml` via workflow_dispatch on the
branch), fix compile errors, bump `pubspec.yaml` to `1.1.0+120`, write `.github/release-notes/v1.1.0+120-beta.12.md`
(Russian, first line `# ProMax 1.1.0 beta 12`), open a PR into `main` (template `.github/PULL_REQUEST_TEMPLATE.md`),
squash-merge it, then `git merge -s ours origin/main` on the branch after checking the trees are identical, and
dispatch both workflows on `main` with input `release_tag: v1.1.0+120-beta.12`. Send the owner the release link,
the IPA and the signed arm64/universal APK links.

Planned after beta 12 (discuss with the owner): beta 13 as release candidate (bug fixes only), stable/beta update
channels (mark betas as GitHub pre-releases + a «Получать бета-версии» switch, default off), an «Экспериментальное»
section (Motion Blur, Android masks/voice, PiP, stickers), then stable `v1.1.0+N`.
