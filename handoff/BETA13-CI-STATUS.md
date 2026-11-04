# Статус CI (второй ИИ) — beta 13

Ветка: `b13-ci` (от `origin/claude/confident-bohr-2dd5e7`, HEAD на момент старта — после `7996f66`).

## 1. macOS: LTO bitcode mismatch

Причина подтверждена логом провала `41806427688` (job `126494480459`, коммит `352c4e5`):
`ld: ... Invalid bitcode version (Producer: '2100.0.123.102.0_0' Reader: '1700.6.4.2_0')` для
`libogg.a`/`libopus.a` внутри `ogg_opus_player` (resolved версия 0.8.0, путь
`darwin/Libs/*.a` — чистый LLVM bitcode, несовместимый с libLTO 17.0.0, которым пользуется
Xcode 26.3 этого раннера.

Исправление: `.github/scripts/build-macos-opus-libs.sh` пересобирает libogg 1.3.5 / opus 1.3.1 /
libopusenc 0.2.1 / opusfile 0.12 (версии взяты из собственных iOS-скриптов пакета) из исходников
xiph.org под arm64 и x86_64 с `-O2` (без `-flto`), lipo в universal, подменяет vendored `.a` в
обоих возможных layout (`darwin/Libs` — 0.8.0, `darwin/*/Frameworks/*.xcframework/macos-arm64_x86_64`
— 0.8.1). Шаг `Rebuild bundled audio libraries without LTO bitcode` добавлен в `macos:` job
`.github/workflows/promax-platforms.yml` между `Dependencies` и `Build`.

Коммит: `a040915` "Rebuild ogg_opus_player macOS libs from source to fix LTO bitcode mismatch"
(https://github.com/stillemptyNOW/ProMax/commit/a040915).

Проверка: `workflow_dispatch` на `b13-ci` — run
https://github.com/stillemptyNOW/ProMax/actions/runs/41809104455 — **в процессе** на момент
записи. Собрать APK/AAB локально нельзя (правило CLAUDE.md), rebuild-скрипт и сеть xiph.org
недоступны из песочницы — реальная проверка только через этот CI run.

Статус: **не подтверждено**, жду завершения job `macos`. Обновлю этот файл с реальным исходом
(успех/провал + лог) сразу после завершения.

## 2. Android: "Expected one Android signer ... found 0"

Диагностика (`352c4e5`, уже на владельческой ветке, не мой коммит) добавляет дамп raw
`apksigner verify --print-certs` вывода при провале. Run `41806427688` на момент записи: job
`android` ещё строит APK (`Build APKs` in progress), шаг `Verify update compatibility` ещё не
выполнялся. Жду завершения, чтобы увидеть реальный диагностический вывод перед тем как чинить
`.github/scripts/verify-android-apks.sh`.

Статус: **расследование не начато** — реальных данных пока нет, следующий шаг сразу после
получения лога.

## Изменённые файлы (b13-ci, коммит a040915)

- `.github/scripts/build-macos-opus-libs.sh` (новый)
- `.github/workflows/promax-platforms.yml` (добавлен шаг в `macos:` job)

Ничего не выпущено, PR не слит, релиз не запущен — жду готовности всех троих.
