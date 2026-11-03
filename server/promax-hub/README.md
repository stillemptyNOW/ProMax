# Сервис ProMax

Основной VPS с 2 ноября 2026 — `2.26.230.233`, публичный адрес `https://proma-x.xyz`. Старый адрес `https://boriskino.qd.je` сохраняется для совместимости beta 12 и старых ссылок. Nginx принимает TLS на внутреннем listener 4443 с PROXY protocol от существующего stream-маршрутизатора. Uvicorn слушает только `127.0.0.1:8091`. Другие vhost и VPN не меняются.

На новом сервере активен выпуск `/opt/promax-hub/releases/beta13-20261102`; исходная база сохранена. `nginx-proma-x.conf` рассчитан на существующий stream и зону `promax_hub`. Для повторного переключения проверенного каталога используется `activate-site.sh /opt/promax-hub/releases/<имя>`: скрипт сохраняет nginx/SQLite и предыдущий путь, проверяет nginx и здоровье сервиса, при ошибке откатывает переключение. Старый `deploy.sh` предназначен для начальной установки и выдаёт новый код администратора; для обычного обновления его не запускать.

На прежнем FI вычисления и база ProMax больше не используются. `nginx-legacy-gateway.conf` направляет запросы beta 12 с boriskino.qd.je на новый VPS по HTTPS с проверкой сертификата и SNI. Для старой установленной PWA сохранены корневые пути ресурсов, новая PWA доступна на `/notifications/`. В каталоге выпуска рядом с `app.py` размещается копия `server/web-push` под именем `notifications`; при запуске из репозитория используется исходный соседний каталог.

Код: `/opt/promax-hub/current`, venv: `/opt/promax-hub/venv`, служба: `promax-hub.service`, данные: `/var/lib/promax-hub/hub.sqlite3` (0700 каталог, 0600 база). Процесс работает под отдельным системным пользователем, с ограничением памяти и прав записи. Внешние access logs для этого vhost отключены.

## Объявления

Все пользователи ProMax видят служебный чат. Только администратор видит закреплённые «Админка» и «Превью». Номер в `HubInbox.adminPhone` определяет видимость UI, но не даёт серверных прав. Ключ админа не встроен в приложение.

Одноразовый код действует сутки, выдаёт отдельный случайный bearer-токен, привязанный к ID аккаунта; код удаляется атомарно после использования. В базе сохраняется только SHA-256 токена. На клиенте токен хранится через `TokenStorage` в системном защищённом хранилище и удаляется при удалении аккаунта.

Получить новый код на VPS:

```sh
cd /opt/promax-hub/current
umask 077
runuser -u promax-hub -- /opt/promax-hub/venv/bin/python manage.py issue-code > /root/promax-admin-activation.txt
```

Код вводится в «Админке» один раз на устройстве. Не отправлять файл кода в Git и не вставлять секрет в URL. `manage.py revoke-admins` отзывает все выданные токены.

Черновик имеет ревизию. Устаревшая ревизия не может перезаписать черновик или опубликоваться. Повторный запрос публикации той же ревизии возвращает то же объявление. Предпросмотр не публикует сообщения. В боевую ленту тестовые сообщения при развёртывании не добавляются.

Клиент синхронизируется при запуске, возвращении на передний план и раз в минуту во время работы. История кешируется отдельно по аккаунтам; повторная загрузка не создаёт дубликаты. Без собственного APNs мгновенная доставка на закрытый iPhone не реализована — это согласовано с владельцем.

## Диагностика

По умолчанию включена и описана в настройках ProMax. Передаются только случайный ID установки, тип ошибки (без текста), ограниченный стек `package:promax*`, версия и платформа. Нет MAX-токенов, номера, ID аккаунта, переписки или локальных путей. При выключении очередь стирается, ожидающие HTTP-запросы отменяются.

До 16 событий в локальной очереди; сервер принимает только разрешённые поля и ограничивает размер и частоту запросов. Это диагностические сведения от недоверенных клиентов, не доказательство подлинности устройства. Срок хранения 14 дней, общий предел 100000 событий.

Прочитать последние диагностические записи:

```sh
cd /opt/promax-hub/current
runuser -u promax-hub -- /opt/promax-hub/venv/bin/python manage.py logs
```

Проверки:

```sh
python -m unittest discover -s tests -v
curl -f https://boriskino.qd.je/health
```

Серверные тесты включены в verify job iOS workflow. Для повторного развёртывания скрипт `deploy.sh` ожидает готовый `/opt/promax-hub/current`; сначала проверяет unit-тесты и `nginx -t`, затем перезапускает только новую службу и делает graceful reload Nginx. Скрипт выдаёт новый код активации; уже активированные токены сохраняются.

## Beta 13 additions

`GET /settings` serves the settings-link landing page. The payload is kept in the URL fragment and never sent to this service. No settings database or upload endpoint is used. The page opens the registered `promax://settings` scheme; the app validates and confirms imports. `/.well-known/assetlinks.json` associates the permanent ProMax Android signing certificate with the domain.

`POST /v1/performance` accepts manually submitted aggregate frame reports when client diagnostics are enabled. It records the random installation ID, version, OS, effect mode/tier, display refresh rate and bounded numeric frame totals/timings. Extra fields are rejected; reports are limited to six per installation per hour and use the existing 14-day telemetry cleanup. They appear in `manage.py logs` with `kind=performance`.
