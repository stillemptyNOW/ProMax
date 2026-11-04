# Статус CI (второй ИИ) — beta 13

Ветка: `b13-ci` (от `origin/claude/confident-bohr-2dd5e7`, после `7996f66`).

## 1. macOS: LTO bitcode mismatch

Причина подтверждена логом провала `41806427688` (job `126494480459`, коммит `352c4e5`):
`ld: ... Invalid bitcode version` для `libogg.a`/`libopus.a` внутри `ogg_opus_player`
(resolved версия 0.8.0, `darwin/Libs/*.a` — чистый LLVM bitcode, несовместимый с libLTO
Xcode 26.3 этого раннера).

Исправление (коммит `a040915`, доработка ретраями `a28f6a6`):
`.github/scripts/build-macos-opus-libs.sh` пересобирает libogg 1.3.5 / opus 1.3.1 /
libopusenc 0.2.1 / opusfile 0.12 из исходников xiph.org под arm64+x86_64 с `-O2` (без `-flto`),
lipo в universal, подменяет vendored `.a`. Шаг добавлен в `macos:` job между `Dependencies` и
`Build`.

**Подтверждено реальным CI-прогоном**: run `41810705854`, job `macos`
(https://github.com/stillemptyNOW/ProMax/actions/runs/41810705854/job/126508938905) —
`Rebuild bundled audio libraries without LTO bitcode`: **success** (87s), `Build` (сам
xcodebuild, линковка): **success** (16 мин). Bitcode-проблема решена.

### 1b. Попутно найден и исправлен баг в `Package`-шаге (не связан с bitcode)

Тот же прогон провалился дальше на `lipo -verify_arch arm64 x86_64 "$app/.../ProMax"` —
`unknown architecture specification flag: .../ProMax`. Причина: `lipo -verify_arch` требует
input-файл ПЕРВЫМ аргументом, затем команду — старый порядок аргументов был неверен с самого
начала (просто никогда не доходило до этого шага, так как job всегда проваливался раньше на
bitcode). Исправлено коммитом `e4fcc06`: `lipo "$app/.../ProMax" -verify_arch arm64 x86_64`.

Статус: **исправлено, ждёт финального прогона** (run `41814429138`, не был отдельно
подтверждён в изоляции, но логика проверена по документации `lipo`).

## 2. Android: "Expected one Android signer ... found 0"

Причина подтверждена реальным логом run `41806427688` (job `android`,
https://github.com/stillemptyNOW/ProMax/actions/runs/41806427688/job/126494480645):
`apksigner verify --print-certs` вывёл **`V2 Signer: certificate SHA-256 digest:
e83be69ec2ea9cc8f418b533636c1a114824bfc05a940fca6060205f390d72b6`** — правильный постоянный
сертификат **присутствовал**, но старый `grep '^Signer #[0-9]*'` матчил только v1-формат
(`Signer #N`), а не v2/v3 (`V2/V3 Signer:`). Наши APK подписаны без v1-схемы, поэтому строк
"Signer #N" не было вовсе → `found 0`, хотя подпись была верной.

Исправление (коммит `48967cb`): `.github/scripts/verify-android-apks.sh` теперь матчит оба
формата (`Signer #N` и `V[0-9.]+ Signer`) и дедуплицирует по digest (а не считает строки) —
один реальный подписант, покрывающий APK несколькими схемами (v1+v2+v3), остаётся одним
подписантом; два разных сертификата всё так же проваливают проверку.

**Подтверждено реальным CI-прогоном**: run `41810705854`, job `android`
(https://github.com/stillemptyNOW/ProMax/actions/runs/41810705854/job/126508938817) — ошибка
"found 0" исчезла, сертификат прошёл проверку.

### 2b. Второй баг, найденный тем же прогоном: `versionCode` для split-APK

После исчезновения ошибки подписи тот же прогон упал на
`Unexpected Android package or version: arm64-v8a`. Причина (нашёл в исходниках Flutter SDK,
`packages/flutter_tools/gradle/.../FlutterPluginConstants.kt`): Flutter's own Gradle plugin
переопределяет `versionCode` для split-per-ABI APK как `abiVersionCode*1000+versionCode`
(1/2/4 для armeabi-v7a/arm64-v8a/x86_64), чтобы у каждого split был уникальный код для Play
Store; universal APK сохраняет обычный versionCode. `lib/core/utils/update_checker.dart`
**уже** снимает этот множитель при сравнении версий (`_abiVersionCodeMultiplier = 1000`) —
то есть проект сознательно полагается на это поведение Flutter, а не отключает его. Значит,
чинить нужно было guard-скрипт, а не gradle.properties (я сначала попробовал отключить через
`force-version-code-ignoring-abi=true`, но откатил — это сломало бы согласованность с
`update_checker.dart`).

Исправление (коммит `12b159f`): скрипт теперь ожидает `base_code` для universal и
`multiplier*1000+base_code` для каждого split-ABI, с той же таблицей multiplier'ов.
`test/verify_android_apks_test.py` обновлён под реальную схему (синтетические `aapt`/
`apksigner` теперь отдают правильные per-ABI коды), добавлен тест на неверный код у universal.
Все 10 python-тестов зелёные локально (`python3 -m unittest verify_android_apks_test -v`).

Статус: **исправлено, ждёт финального прогона** (run `41814429138`, in progress на момент
записи).

## Изменённые файлы (b13-ci)

- `.github/scripts/build-macos-opus-libs.sh` (новый, коммиты `a040915`, `a28f6a6`)
- `.github/workflows/promax-platforms.yml` (шаг rebuild + lipo fix, коммиты `a040915`, `e4fcc06`)
- `.github/scripts/verify-android-apks.sh` (signer-matching + per-ABI versionCode, коммиты
  `48967cb`, `12b159f`)
- `test/verify_android_apks_test.py` (синтетические стабы под реальную схему, коммит `12b159f`)

Финальный прогон со всеми тремя фиксами: run `41814429138`
(https://github.com/stillemptyNOW/ProMax/actions/runs/41814429138) — в процессе, обновлю этот
файл реальным результатом сразу после завершения. Ничего не выпущено, PR не слит, релиз не
запущен.
