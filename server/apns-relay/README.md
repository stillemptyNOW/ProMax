# Экспериментальный WebPush → APNs для ProMax

Сервер для собственного iPhone или доверенных устройств владельца. Он создаёт WebPush-подписку, проверяет VAPID подпись MAX, расшифровывает RFC 8291 payload и отправляет через APNs общее уведомление без текста сообщения. Это не готовый общедоступный push-сервис. Совместимость собственного endpoint с сервером MAX пока не проверена на реальном аккаунте.

## Что требуется

- Apple Developer App ID, совпадающий с подписанным ProMax, и профиль с Push Notifications.
- Ключ APNs `.p8`, его Key ID и Team ID от той же команды Apple Developer.
- Постоянный HTTPS сервер с публичным DNS и действующим сертификатом TLS, доступом к APNs по HTTP/2.
- Python 3.12+, приватная директория данных и секрет регистрации минимум 32 символа.

Для общего сертификата eSign без доступа к Apple Developer владельца этих ресурсов недостаточно. `.p12` сертификат подписи приложения не заменяет ключ отправки APNs.

`GET /health` показывает состояние конфигурации. `deliveryReady: true` подтверждает только загрузку ключа, а не доставку на iPhone. Без ключа сервер возвращает `awaiting_apns` и не разрешает регистрацию подписок.

## Запуск

```sh
python -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m unittest discover -s tests -v
```

Задайте переменные из `.env.example` в окружении службы. Файл `.env` автоматически не читается. Сгенерировать секрет можно командой `python -c 'import secrets; print(secrets.token_urlsafe(48))'`. Храните `.p8` вне checkout, с правами `0600`. `PROMAX_RELAY_URL` должен быть HTTPS origin без пути. `APNS_BUNDLE_ID` должен точно совпадать с подписью приложения.

```sh
.venv/bin/uvicorn app:app --host 127.0.0.1 --port 8080 --no-access-log
```

Выведите службу наружу через HTTPS reverse proxy. Ограничьте запрос 64 KiB, время запроса и частоту запросов. Отключите запись URI `/webpush/` и заголовков Authorization в логах proxy: endpoint является идентификатором подписки. Не открывайте внутренний порт uvicorn в интернет. Каталог `data/` и резервные копии содержат токены устройств и ключи WebPush; они должны оставаться приватными.

В ProMax откройте настройки уведомлений → прямые push, авторизуйте WEB-сессию MAX, укажите HTTPS origin и секрет, подключите устройство. Выдача токена APNs и регистрация подписки ещё не подтверждают доставку: отправьте сообщение с другого аккаунта при закрытом ProMax и проверьте результат. После переустановки, смены сертификата или токена нужно подключить устройство снова.

## Ограничения

Секрет регистрации общий для владельца сервера; публичная многопользовательская эксплуатация не поддерживается. Сервер не отправляет VoIP PushKit, не будит приложение для синхронизации и не реализует CallKit. APNs сообщения содержат общий текст и ID чата, когда он присутствует в payload MAX. Изменение схемы или VAPID ключа MAX может потребовать обновления. Отмена подписки доступна через `DELETE /v1/subscriptions/{id}` с `Authorization: Bearer ...`.

Стандарты: [RFC 8291](https://www.rfc-editor.org/rfc/rfc8291), [RFC 8292](https://www.rfc-editor.org/rfc/rfc8292). Apple: [регистрация APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) и [aps-environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment).
