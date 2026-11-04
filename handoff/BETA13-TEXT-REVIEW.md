# Отчёт по ревизии текстов интерфейса ProMax (Beta 13)

**Дата проверки:** 4 ноября 2026 г.  
**Целевая ветка:** `claude/confident-bohr-2dd5e7`  
**Ветка отчёта:** `review/beta13-text-review`  
**Файлы локализации:** `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb`

---

## 1. Сводка аудита

- **Объём базы строк:** по **2 398 ключей** в каждом файле (`app_ru.arb` и `app_en.arb`).
- **Синхронность ключей:** **100% паритет** (все ключи присутствуют в обоих файлах, пропущенных ключей между RU и EN нет).
- **Фокус аудита:** экран настроек ProMax, ProMax Hub, внешний вид, облачное хранилище, безопасность, шрифты, темы оформления, информация о системе/сервере и производительность.
- **Статус приложения:** изменения в исходный код и существующие файлы локализации в рамках данной ветки намеренно **не вносились**, чтобы исключить конфликты со смежными задачами бета-релиза 13. Ниже представлены конкретные выявленные проблемы с точными путями, строками и предлагаемыми исправлениями.

---

## 2. Орфографические и грамматические ошибки в русском языке

### 2.1. Грубая опечатка в слове «конфиденциальность»
- **Файл:** `lib/l10n/app_ru.arb` (строка 1960) / `lib/l10n/app_en.arb` (строка 2323)
- **Ключ:** `settingsTabCloudStoragePrivacyTitle`
- **Текущий текст (RU):** `"Не обеспечивается конфединциальность файлов"`
- **Текущий текст (EN):** `"File privacy is not guaranteed"`
- **Проблема:** Допущена грубая опечатка в слове — «конфе**дин**циальность» вместо «конфе**ден**циальность» / «конфиденциальность».
- **Предлагаемое исправление:**
  ```json
  "settingsTabCloudStoragePrivacyTitle": "Не обеспечивается конфиденциальность файлов"
  ```

### 2.2. Ошибка в написании слова «объём» (мягкий знак вместо твёрдого)
- **Файл:** `lib/l10n/app_ru.arb` (строка 1959) / `lib/l10n/app_en.arb` (строка 2322)
- **Ключ:** `settingsTabCloudStorageLimitsBody`
- **Текущий текст (RU):** `"Можете хранить массивный обьем информации."`
- **Текущий текст (EN):** `"Store a massive amount of information."`
- **Проблема:** Использован мягкий знак вместо твёрдого знака («обьем»).
- **Предлагаемое исправление:**
  ```json
  "settingsTabCloudStorageLimitsBody": "Можете хранить массивный объём информации."
  ```

### 2.3. Грамматическая ошибка в предлоге времени («в течении» вместо «в течение»)
- **Файл:** `lib/l10n/app_ru.arb` (строка 170)
- **Ключ:** `infoEditTimeout`
- **Текущий текст (RU):** `"Можно редактировать сообщение в течении:"`
- **Проблема:** Производный предлог времени пишется с буквой «е» на конце: «в течение». «В течении» используется только для обозначения русла реки/воды.
- **Предлагаемое исправление:**
  ```json
  "infoEditTimeout": "Можно редактировать сообщение в течение:"
  ```

---

## 3. Технические идентификаторы (Slugs) вместо пользовательского текста

В блоке системных настроек и информации о возможностях сервера/инстанса ряд строк оставлен в виде сырых kebab-case слагов (особенно в `app_en.arb`, а часть — в обоих языках):

| Ключ | Файл и строка | Текущее значение | Предлагаемое значение |
|---|---|---|---|
| `infoEditTimeout` | `lib/l10n/app_en.arb`: 170 | `"edit-timeout"` | `"Message editing allowed within:"` |
| `infoAccountRemovalEnabled` | `lib/l10n/app_en.arb`: 158 | `"account-removal-enabled"` (RU: `"Мгновенное удаление аккаунта:"`) | `"Instant account deletion:"` |
| `infoDeleteForAll` | `lib/l10n/app_en.arb`: 1750 | `"delete-for-all"` (RU: `"Удаление чата у собеседника (delete-for-all):"`) | `"Delete chat for everyone:"` |
| `infoFileUploadTypes` | `lib/l10n/app_en.arb`: 127 | `"file-upload-unsupported-types"` (RU: `"запрещённые типы файлов"`) | `"Unsupported file upload types:"` |
| `infoWhiteListLinks` | `lib/l10n/app_en.arb`: 128 | `"white-list-links"` (RU: `"безопасные ссылки"`) | `"Allowed links whitelist:"` |
| `infoMaxMsgLength` | `lib/l10n/app_en.arb`: 162 | `"max-msg-length"` (RU: `"макс. длина сообщения:"`) | `"Maximum message length:"` |
| `infoSendLocationEnabled` | `lib/l10n/app_en.arb`: 165 | `"send-location-enabled"` (RU: `"отправка гео.:"`) | `"Location sharing:"` |
| `infoVideoMsgEnabled` | `lib/l10n/app_en.arb`: 168 | `"video-msg-enabled"` (RU: `"Кружки:"`) | `"Video messages:"` |
| `infoAccountNicknameEnabled` | `lib/l10n/app_ru.arb`: 173<br>`lib/l10n/app_en.arb`: 173 | `"account-nickname-enabled"` (в обоих файлах) | RU: `"Никнейм аккаунта:"`<br>EN: `"Account nickname:"` |
| `infoCallsEndpoint` | `lib/l10n/app_ru.arb`: 159<br>`lib/l10n/app_en.arb`: 159 | `"calls-endpoint"` (в обоих файлах) | RU: `"Эндпоинт звонков:"`<br>EN: `"Calls endpoint:"` |
| `infoQuotesEnabled` | `lib/l10n/app_ru.arb`: 160<br>`lib/l10n/app_en.arb`: 160 | `"quotes-enabled"` (в обоих файлах) | RU: `"Цитаты:"`<br>EN: `"Quotes:"` |
| `infoReactionsEnabled` | `lib/l10n/app_ru.arb`: 161<br>`lib/l10n/app_en.arb`: 161 | `"reactions-enabled"` (в обоих файлах) | RU: `"Реакции:"`<br>EN: `"Reactions:"` |
| `infoImageQuality` | `lib/l10n/app_ru.arb`: 163<br>`lib/l10n/app_en.arb`: 163 | `"image-quality"` (в обоих файлах) | RU: `"Качество изображений:"`<br>EN: `"Image quality:"` |
| `infoImageSize` | `lib/l10n/app_ru.arb`: 164<br>`lib/l10n/app_en.arb`: 164 | `"image-size"` (в обоих файлах) | RU: `"Размер изображений:"`<br>EN: `"Image size:"` |
| `infoUnsafeFilesAlert` | `lib/l10n/app_ru.arb`: 166<br>`lib/l10n/app_en.arb`: 166 | `"unsafe-files-alert"` (в обоих файлах) | RU: `"Предупреждение о небезопасных файлах:"`<br>EN: `"Unsafe files warning:"` |
| `infoVoiceMsgEnabled` | `lib/l10n/app_ru.arb`: 167<br>`lib/l10n/app_en.arb`: 167 | `"voice-msg-enabled"` (в обоих файлах) | RU: `"Голосовые сообщения:"`<br>EN: `"Voice messages:"` |
| `infoChannelAvatarEnabled` | `lib/l10n/app_ru.arb`: 169<br>`lib/l10n/app_en.arb`: 169 | `"channel-avatar-enabled"` (в обоих файлах) | RU: `"Аватары каналов:"`<br>EN: `"Channel avatars:"` |
| `infoPushEnabled` | `lib/l10n/app_ru.arb`: 171<br>`lib/l10n/app_en.arb`: 171 | `"push-enabled"` (в обоих файлах) | RU: `"Push-уведомления:"`<br>EN: `"Push notifications:"` |
| `infoCanCreateGroup` | `lib/l10n/app_ru.arb`: 172<br>`lib/l10n/app_en.arb`: 172 | `"can-create-group"` (в обоих файлах) | RU: `"Создание групп:"`<br>EN: `"Group creation:"` |
| `infoDeviceSessionHistory` | `lib/l10n/app_ru.arb`: 174<br>`lib/l10n/app_en.arb`: 174 | `"device-session-history"` (в обоих файлах) | RU: `"История сессий устройств:"`<br>EN: `"Device session history:"` |
| `infoPinMessage` | `lib/l10n/app_ru.arb`: 175<br>`lib/l10n/app_en.arb`: 175 | `"pin-message"` (в обоих файлах) | RU: `"Закрепление сообщений:"`<br>EN: `"Message pinning:"` |

---

## 4. Стилистические и терминологические замечания

1. **Градации производительности (`performanceTier*`)**:
   - `performanceTierLow`: RU: `"слабое"`, EN: `"entry-level"` (RU строка 2387, EN строка 2756).
   - `performanceTierMid`: RU: `"среднее"`, EN: `"mid-range"` (RU строка 2388, EN строка 2757).
   - `performanceTierHigh`: RU: `"мощное"`, EN: `"high-end"` (RU строка 2389, EN строка 2758).
   - *Замечание:* В русском интерфейсе устройства названы простыми прилагательными («слабое», «среднее», «мощное»), тогда как в английском — общепринятыми технологическими терминами («entry-level», «mid-range», «high-end»). Это допустимо и интуитивно понятно, но при желании унификации в RU можно рассмотреть: «начальный уровень», «средний уровень», «высокий уровень».
2. **Плюральные формы ICU (`uploadNotificationPhotos`)**:
   - `lib/l10n/app_ru.arb` (строка 191): `"{count, plural, =1{Фото} other{{count} фото}}"`
   - `lib/l10n/app_en.arb` (строка 191): `"{count, plural, =1{Photo} other{{count} photos}}"`
   - *Замечание:* В RU форме `=1{Фото}` отсутствует переменная `{count}` (выводится просто "Фото"), в то время как в английском `=1{Photo}` или `other` ожидается число. Работает корректно, но стоит помнить при интеграции с контекстом уведомлений.

---

## 5. Проверенные экраны и компоненты интерфейса

Были проверены все локализационные ключи и исходные файлы UI экранов настроек:
1. **Экран основных настроек ProMax**: `lib/frontend/screens/profile/promax_settings_screen.dart`
2. **Экран внешнего вида и тем оформления**:
   - `lib/frontend/screens/profile/appearance_screen.dart`
   - `lib/frontend/screens/profile/theme_settings_screen.dart`
   - `lib/frontend/screens/profile/font_settings_screen.dart`
3. **Экраны ProMax Hub**:
   - `lib/frontend/screens/profile/hub_settings_screen.dart`
   - `lib/frontend/screens/promax_hub/*.dart`
4. **Облачное хранилище**: `lib/frontend/screens/profile/cloud_storage_screen.dart`
5. **Вкладка профиля и настроек**: `lib/frontend/screens/profile/settings_tab.dart`
6. **Настройки платформы и производительности**: `lib/frontend/screens/profile/platform_settings_screen.dart`
7. **Экран информации о сервере и ограничениях**: `lib/frontend/screens/profile/info_screen.dart`
8. **Конфигурационные файлы**: `lib/core/config/*.dart`
9. **Словари локализации**: `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` (все 2 398 ключей).

---

## 6. Рекомендация к применению

Данные исправления рекомендуется применить отдельным точечным коммитом в ARB-файлы после завершения текущей параллельной сборки и стабилизации ветки `claude/confident-bohr-2dd5e7`, выполнив последующую генерацию кода через `flutter gen-l10n`.
