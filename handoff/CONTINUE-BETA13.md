# Продолжение beta 13

Состояние: 3 ноября 2026. Этот файл — оперативная передача; перед работой сверить `git status` и активных агентов. Работа НЕ закончена, beta 13 НЕ опубликована, CI ещё НЕ запускался для нынешнего дерева.

## Поручение владельца

Все задачи остаются в beta 13, версия `1.1.0+121`; переносить часть в beta 14 владелец запретил. Нужны: починка и улучшение админки, перенос всех сервисов ProMax на новый VPS, красивый поиск по номеру, самостоятельный редизайн чатов и профиля с классическим переключателем, ОС/отметка ProMax по согласию, sender-key шифрование групп через C, зашифрованные общие обои через Hub, чтение при реакции/ответе/отправке. Затем пробные `workflow_dispatch` на ветке, PR в main по шаблону, squash, сверка деревьев ветки и main, оба workflow на main, выпуск с IPA и постоянной подписью APK.

Дополнительно сайт: самостоятельный тёмный дизайн, macOS загрузка, серверный счётчик начатых загрузок с начальным значением 1; растёт от реальных нажатий на действующие ссылки. Komet — только ориентир по составу информации, внешне не копировать. Telegram — только дизайн/поведение, не копировать код GPL-2.0 или ассеты. Анимация около 15 секунд только с текстом «Добро пожаловать в редизайн» на первый запуск после обновления; владелец назвал beta 14, хотя весь выпуск требует в beta 13 — не переименовывать сборку автоматически.

Админский UI должен проверять одновременно номер и ID владельца, указанные в переписке. Это не серверное удостоверение: не выдавать права по произвольному присланному ID/номеру. Сохранять проверку секретного токена/подтверждения. Владелец подтвердил, что официального бота MAX пока нет; объяснено, что он нужен для проверяемой подписи аккаунта. Нынешний Hub имеет только код активации администратора, полноценной аттестации обычных MAX-аккаунтов в нём нет. Нельзя называть самообъявленный ID подтверждённым.

## Окружение и правила

- Репозиторий: `C:\Users\7ims (admin)\Documents\ChatGPT\ProMax`.
- Ветка: `claude/confident-bohr-2dd5e7`, HEAD до изменений `07e665c6680b0e65aff1fcdc74d89b08a7035e01`. Из `codex/settings-links` переключились с тем же HEAD без потери правок. Много изменений в рабочем дереве, пока без нового коммита. Выпуск/PR/squash явно разрешены пользователем.
- Читать AGENTS.md и CLAUDE.md. Не добавлять комментарии в код, только синтетические тестовые данные, showCustomNotification/showHintBubble вместо SnackBar, Lottie для переключения перечёркивания. Всё подписанное отменять в dispose.
- PowerShell: `login:false`, явный workdir. Approval never, не задавать sandbox_permissions.
- Flutter `C:\tools\flutter-promax\bin\flutter.bat`, версия 3.47.0. Перед тестами TEMP/TMP=`D:\ProMax-build-temp`. Локально APK/AAB НЕ собирать.
- После ARB: `flutter gen-l10n`; проверка `flutter analyze --no-pub lib test tool native/promax_effects/lib` и полный `flutter test --no-pub`. Analyze без `--no-pub` однажды завис после pub get; завершили только собственные PID, повтор без pub занял 5 секунд.
- Python Hub: `C:\tools\promax-hub-venv\Scripts\python.exe`, тесты из `server/promax-hub`: `-m unittest discover -s tests`.
- SSH/SCP: `C:\Program Files\Git\usr\bin\ssh.exe` и `scp.exe`; существующий ключ `%USERPROFILE%/.ssh/aether`. Не читать/печатать ключи и пароли. GitHub gh авторизован.
- Протокол docs был указан README, но отсутствовал; агент создал новый `native/promax_crypto/docs/PROTOCOL.md`. `.gitignore` исключает `docs/` на разных уровнях: для разрешённых протокольных/дизайн-документов нужен точечный `git add -f`, не добавлять все игнорируемые документы.

## Действующие агенты

- `beta13_android_icons`: поиск завершён; теперь собственный редизайн списка/экрана чата. Договорён `AppDesign.classic` ValueNotifier<bool>, `load()`, `saveClassic(bool)`, ключ `promax_classic_design`, default false. Сам создаёт AppDesign. Профильный агент подключает startup/переключатель. Дизайн-документ `docs/superpowers/specs/2026-11-03-beta13-chat-design.md`.
- `beta13_settings_performance`: админка и read-on-action закончены; теперь профиль, общее представление self-preview, классический переключатель/startup и приветственная анимация. Изменяет ARB и запускает gen-l10n по согласованию.
- `beta13_group_crypto`: C sender keys, docs, FFI. Нативное ядро проходит полный make test на VPS в отдельном `/tmp/promax-group-crypto-20261103`. ASan и дополнительные тесты/FFI ещё проверить. Это пока примитивы, НЕ готовая интеграция группы в приложение; нужны проверенные identities, согласие и достоверное членство/epoch.

Агенты пережили ошибки лимита и временный 403; их работа сохранена. Следить за сообщениями, не перетирать их файлы. Одновременно только один процесс Flutter test/analyze, слот согласовывать.

## Уже реализовано

Более ранняя работа: настройки по HTTPS fragment-ссылке и файлу с whitelist и подтверждением, разделение общих и платформенных настроек, адаптация эффектов по агрегатам кадров, incremental Hub polling, диагностика/числовые отчёты на VPS, четыре новые праздничные иконки (Christmas/Valentine/WomensDay/VictoryDay), все сезоны 7 дней, сайт/Telegram кнопки, новый единый ProductLinks, проверка постоянной подписи Android в CI. Подробности в BETA13-AUDIT.md и release-notes.

Админка: HubInbox защищает смену аккаунта, порядок/ревизии, повтор сохранения, конфликт retry, подтверждённую ревизию публикации, успешную публикацию при сбое последующего refresh. Редактор не стирает несохранённый текст при refresh/reopen в сеансе. 18 focused tests прошли. Проверка одновременно номера и ID по последнему поручению ещё НЕ внесена.

Поиск: отдельные контроллеры phone/ID, страна и формат номера, scrollable sheet над клавиатурой, mounted/account/session guards, защита duplicate submit; ContactsModule.findByPhone имеет опциональный cacheResult для исключения загрязнения кэшей после account switch. 19 focused tests прошли. Снимок `D:\ProMax-build-temp\contact-preview\phone-search.png`.

Read on action: reaction/reply/send opt-in bools по умолчанию off в ProMaxSettings, action_read_receipt.dart, интеграция messages.dart/AppDatabase. Успешные действия, граница по конкретному сообщению; scheduled/system не включены, errors чтения не ломают send; LocalReadState beta12 не изменён. 42 +40 focused tests прошли, 2 nativecrypto-skipped во втором наборе. 5 ключей RU/EN сгенерированы.

Сайт: тёмная палитра, macOS selector и автоопределение, count API/SQLite, сохранение счётчика и идемпотентность event id. В браузере завершение загрузки с GitHub неизвестно — подпись «Начатые загрузки» и пояснение начального значения. Никаких cookies/постоянных пользовательских ID для счётчика. Тесты Hub17 и Node downloads прошли.

macOS job добавлен в promax-platforms.yml: macos-15, Rust обеих архитектур, Flutter config-only + xcodebuild unsigned universal, lipo verify, ditto ZIP. Ещё НИ РАЗУ не выполнялся — обязательно пробный CI и исправления. Сайт не показывает действующую ссылку на отсутствующий asset. Имя ожидается ProMax-macos-universal.zip.

## VPS и опубликованный сайт

- Новый VPS root@`2.26.230.233`, домен https://proma-x.xyz/, Ubuntu22.04. Доступ и публикация прямо разрешены прежним поручением. Не спрашивать их повторно.
- Текущий `/opt/promax-hub/current` -> `/opt/promax-hub/releases/site-dark-20261103`. Uvicorn только127.0.0.1:8091, promax-hub.service под promax-hub. venv `/opt/promax-hub/venv`.
- Данные `/var/lib/promax-hub/hub.sqlite3`, каталог0700/файл0600. Сохранять базу! Не заменять тестовой, не публиковать тестовые объявления, не перевыдавать/отзывать настоящие ключи.
- Перед последней сменой backup `/root/promax-site-backup.008PwT`, скрипт activate-site.sh делает SQLite backup/rollback и nginx-t. Cleanup timer active.
- PWA уведомлений перенесена на https://proma-x.xyz/notifications/, source server/web-push в deployment копируется под release/notifications. Относительные пути/worker корректны в подпапке, Node9tests green.
- Старый FI alias=root@2.26.228.18, boriskino.qd.je DNS остаётся на нём. Прежний Hub service+timer остановлены/disabled; nginx теперь ТОЛЬКО совместимый HTTPS шлюз к новому VPS. Файл source nginx-legacy-gateway.conf, upstream HTTPS2.26.230.233, SNI/Host proma-x.xyz, CA verify on/depth3. Старые rootPWA ресурсы перенаправляются в notifications, API сохраняет пути и Authorization. Старый health/announcements/root и новый health/announcements/notifications дали200.
- Прежний gateway backup `/root/promax-gateway-backup.*`. VPN/другие сервисы не трогать.
- Последний deploy: `C:\tools\promax-site-dark.tgz`; сайт уже тёмный, count GET вернул1. Никаких fake click POST в боевой базе не выполняли.
- CUA/browser ранее работал, но после перезапуска 3 ноября ошибка «failed to write kernel assets: system cannot find path». reset не помог. Новую тёмную версию ещё НЕ проверили визуально в браузере. Не обходить TLS ошибки; HTTPS с VPS проверен.

## Выпуск и обязательные оставшиеся работы

1. Закончить все текущие агентские задачи. Ничего не объявлять реализованным только по наличию API/примитивов.
2. Реализовать проверяемую обычную identity Hub. Официальная документация подтверждает Mini App initData HMAC-SHA256 через ключ WebAppData и bot token: https://dev.max.ru/docs/webapps/validation . На сервере строгие duplicate-параметры, срок auth_date, constant-time сравнение, не хранить raw initData/номера/MAXсессионные токены. Существующий backend/webapp.dart может получать подписанный launch URL своего бота, когда бот будет создан. Пока бот отсутствует — существенная зависимость, не ослаблять проверку.
3. Реализовать opt-in presence OS TTL несколько минут и opt-in badge, оба off default, без раскрытия выключенного пользователя; учитывать смену аккаунта, общий Hub poll, удаление всех данных пользователя кнопкой.
4. Зашифрованные общие обои через native core + Hub opaque files/capabilities, согласие на приём/свои, пауза live в фоне/Performance.
5. Интегрировать C sender keys в группы, authoritative membership/join/leave rotation, согласие всех, предупреждение/auto-disable при несовместимом участнике. Не подменять sender keys legacy passphrase.
6. Одновременно номер+ID admin UI, сохранение серверных прав; диагностическая админка/роли требуют законченного решения.
7. Анализ и полный тест, нативные test/ASan. Последняя полная проверка ДО новых read/redesign/crypto —1557passed13skipped, её нельзя выдавать за финальную.
8. Изучить статус git/новые файлы; секреты/локальные mediaoutput/node_modules исключены. В release-notes честно все изменения/ограничения. `pubspec.yaml` уже1.1.0+121.
9. Commit/push на пользовательскую ветку разрешён выпуском. Запустить оба workflow_dispatch на ветке БЕЗ release_tag, дождаться всех jobs, исправить (особенно новый macOS). Затем PR по шаблону, squash main, убедиться в равенстве деревьев и синхронизировать ветку без потери истории/чужих правок. Запустить оба workflow main с release_tag и контролируемой публикацией (можно draft до готовности всех файлов), финальные ссылки на release/IPA/APK.
10. Постоянная подпись promax beta11/12 SHA256 e83be69ec2ea9cc8f418b533636c1a114824bfc05a940fca6060205f390d72b6. Старый beta11preview подписан другим ключом, которого не нашли; бесшовный переход preview→promax обычным APK невозможен. Не обещать обратное.

## Идеи серверных функций по официальным возможностям MAX

Собственный Hub: каталог тем, согласованная синхронизация настроек с шифрованием, состояние сервиса, диагностика, объявления ProMax. Официальный Bot API: поддержка с inline-кнопками, miniapp, HTTPS webhook, управление разрешёнными чатами/каналами по правам бота. Это не разрешение на любую массовую рассылку или поиск произвольных номеров. Open Client API для альтернативных клиентов — отдельная программа, доступа у ProMax не подтверждено.

Источники: https://dev.max.ru/docs-api , https://dev.max.ru/docs-api/use-cases/event-notifications/ , https://dev.max.ru/docs-api/use-cases/sending-messages/keyboard/ , https://dev.max.ru/docs/open-api/ , https://dev.max.ru/docs/legal/requirements . Требования bot/miniapp запрещают ряд сервисных/массовых рассылок вне договора, не переносить их автоматически на собственный Hub.

## Промпт для другой ИИ

«Продолжи разработку ProMax beta13 в C:\Users\7ims (admin)\Documents\ChatGPT\ProMax, ветка claude/confident-bohr-2dd5e7. Сначала прочитай AGENTS.md, CLAUDE.md и handoff/CONTINUE-BETA13.md, проверь git status и активных агентов. Не начинай заново и не теряй некоммиченные изменения. Владелец требует ВСЕ согласованные функции в beta13, не beta14; законченный выпуск1.1.0+121 через пробные CIнаветке, PRsquashmain, оба workflowmain, подписанныеAPK+IPA+macOS. Не публикуй недоделанную криптографию/фиктивные verifiedIDs. Официального бота MAX пока нет, подтверждение обычных аккаунтов — открытая зависимость. Новый VPS2.26.230.233/promа-x.xyz уже доступен существующимSSHключом, сайт/API/PWAперенесены, старыйFIтолькогateway; не перезаписывайSQLite и не трогайVPN. Сохраняй подробный прогресс в handoff, не печатайсекреты, локальноAPK/AABнесобирать. Доводи текущую задачу до результата и сообщай точные блокеры, без выдуманных процентов готовности.»
