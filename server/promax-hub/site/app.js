import {assetsFor, assetLabel, chooseRelease, detectPlatform, formatSize, safeDownload} from './release-utils.mjs';
import {recordDownload} from './download-counter.mjs';

const byId = id => document.getElementById(id);
const showDownloads = count => {
  byId('download-count').textContent = Number.isSafeInteger(count) && count >= 1 ? count.toLocaleString('ru-RU') : '—';
};
fetch('/v1/downloads').then(response => response.ok ? response.json() : Promise.reject()).then(value => showDownloads(value.started)).catch(() => showDownloads(null));
for (const id of ['hero-download', 'asset-download']) {
  byId(id).addEventListener('click', event => {
    const asset = event.currentTarget.getAttribute('href');
    if (!safeDownload(asset)) return;
    const key = crypto.randomUUID().replaceAll('-', '');
    recordDownload(asset, key).then(showDownloads).catch(() => {});
  });
}
const labels = {android: 'Android', ios: 'iPhone', windows: 'Windows', macos: 'macOS', linux: 'Linux'};
const detected = detectPlatform(navigator.userAgent, navigator.platform, navigator.maxTouchPoints);
let platform = detected ?? 'android';
let releases = [];
let currentRelease = null;
let currentAssets = [];
let stale = false;
const instructions = {
  android: ['Скачай подходящий APK. Универсальный вариант подходит всем поддерживаемым архитектурам.', 'Открой файл. Если Android попросит разрешение установки для браузера, предоставь его этому источнику.', 'Подтверди установку и войди в свой аккаунт MAX.'],
  ios: ['Скачай IPA на iPhone или компьютер.', 'Подпиши файл своим сертификатом через совместимый инструмент, например eSign или AltStore.', 'Установи подписанную копию и войди в аккаунт. Прямая установка неподписанного IPA в iOS недоступна.'],
  windows: ['Скачай установщик .exe. Для запуска без установки выбери Portable.', 'Запусти установщик и выбери папку. Portable-архив сначала распакуй полностью.', 'Открой ProMax. В установленной версии доступны встроенные обновления.'],
  linux: ['Скачай архив Linux x64.', 'Распакуй архив целиком, сохраняя папки lib и data рядом с приложением.', 'Запусти ProMax из распакованной папки. Системе могут понадобиться библиотеки GTK и мультимедиа.'],
  macos: ['Скачай ZIP для macOS и распакуй его.', 'Перенеси ProMax.app в папку «Программы». Архив подходит для Apple Silicon и Intel.', 'Бета не подписана Developer ID и не нотарифицирована Apple. Если macOS блокирует запуск, проверь источник и контрольную сумму файла; решение о запуске принимай в настройках безопасности macOS.'],
};

const hints = {
  android: 'Подписанные APK из официального репозитория ProMax. Android 6.0 и новее.',
  ios: 'Файл IPA без подписи. Для установки нужен собственный сертификат или совместимый способ sideload.',
  windows: 'Установщик для Windows x64 и переносимый ZIP-архив.',
  linux: 'Готовый архив для Linux x64. Необходимо графическое окружение с GTK.',
  macos: 'Универсальное приложение для Apple Silicon и Intel. Без подписи Developer ID и нотарификации Apple.',
};

for (const button of document.querySelectorAll('.theme-dot')) {
  button.addEventListener('click', () => {
    byId('demo-phone').dataset.theme = button.dataset.theme;
    for (const item of document.querySelectorAll('.theme-dot')) {
      const selected = item === button;
      item.classList.toggle('selected', selected);
      item.setAttribute('aria-pressed', String(selected));
    }
  });
}

for (const button of document.querySelectorAll('[data-platform]')) {
  button.addEventListener('click', () => {
    platform = button.dataset.platform;
    selectChannel(true);
  });
}

function renderPlatform() {
  for (const button of document.querySelectorAll('[data-platform]')) {
    const active = button.dataset.platform === platform;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  }
  byId('platform-title').textContent = `ProMax для ${labels[platform]}`;
  byId('platform-hint').textContent = hints[platform];
  byId('install-steps').replaceChildren(...instructions[platform].map(text => {
    const item = document.createElement('li');
    item.textContent = text;
    return item;
  }));
  byId('install-note').textContent = platform === 'android'
    ? 'Обновление поверх требует той же подписи. Старый preview beta 11 использует другой ключ: перед однократным переходом сохрани нужные локальные данные.'
    : platform === 'ios' ? 'Перевод сообщений требует iOS 18+, создание стикеров — iOS 17+. Объявления обновляются при работе приложения.'
    : 'Если нужная сборка ещё не прикреплена к выпуску, выбери предыдущую версию или проверь страницу GitHub.';
}

function selectChannel(preferAvailable = false) {
  const channel = byId('channel').value;
  const available = releases.filter(release => channel === 'beta' ? release.beta : !release.beta);
  const previous = byId('release').value;
  byId('release').replaceChildren(...available.map(release => new Option(release.name, release.tag)));
  currentRelease = !preferAvailable && available.find(release => release.tag === previous) || chooseRelease(releases, channel, platform);
  if (currentRelease) byId('release').value = currentRelease.tag;
  else byId('release').append(new Option(channel === 'stable' ? 'Стабильных выпусков пока нет' : 'Выпусков пока нет', ''));
  renderRelease();
}

function renderRelease() {
  renderPlatform();
  byId('release-label').textContent = currentRelease ? currentRelease.name : 'Выбери другой канал';
  byId('release-source').href = currentRelease?.url ?? 'https://github.com/stillemptyNOW/ProMax/releases';
  currentAssets = assetsFor(currentRelease, platform).filter(asset => safeDownload(asset.url));
  byId('format').replaceChildren(...currentAssets.map((asset, index) => new Option(assetLabel(asset), String(index))));
  byId('format-label').hidden = currentAssets.length <= 1;
  renderAsset();
  renderNotes();
}

function renderAsset() {
  const asset = currentAssets[Number(byId('format').value) || 0];
  const button = byId('asset-download');
  button.setAttribute('aria-disabled', String(!asset));
  if (asset) button.href = asset.url;
  else button.removeAttribute('href');
  button.tabIndex = asset ? 0 : -1;
  button.textContent = asset ? `Скачать ${platform === 'android' ? 'APK' : platform === 'ios' ? 'IPA' : platform === 'windows' && asset.name.endsWith('.exe') ? 'для Windows' : 'архив'} ↓` : 'Файл ещё не опубликован';
  byId('file-meta').textContent = asset ? `${formatSize(asset.size)} · ${asset.name}` : '';
  byId('checksum').hidden = !asset?.sha256;
  byId('digest').textContent = asset?.sha256 ?? '';
  byId('download-status').textContent = !currentRelease
    ? 'В этом канале пока нет выпусков. Выбери «Бета» или открой GitHub.'
    : !asset ? 'Выбери другую версию или проверь этот выпуск на GitHub.'
    : stale ? 'Показан последний сохранённый список: GitHub временно недоступен.' : 'Файл загружается напрямую с GitHub.';
}

function renderNotes() {
  byId('notes-title').textContent = currentRelease?.name ?? 'Изменения выпуска';
  const root = byId('release-notes');
  root.replaceChildren();
  let list;
  for (const raw of (currentRelease?.notes || 'Описание будет доступно на странице выпуска в GitHub.').split('\n')) {
    const line = raw.trim();
    if (!line) { list = null; continue; }
    if (/^#{1,6}\s/.test(line)) {
      const heading = document.createElement('h3');
      heading.textContent = line.replace(/^#{1,6}\s+/, '');
      root.append(heading);
      list = null;
    } else if (/^[-*]\s/.test(line)) {
      if (!list) { list = document.createElement('ul'); root.append(list); }
      const item = document.createElement('li');
      item.textContent = line.replace(/^[-*]\s+/, '').replace(/`/g, '');
      list.append(item);
    } else {
      const paragraph = document.createElement('p');
      paragraph.textContent = line.replace(/`/g, '');
      root.append(paragraph);
      list = null;
    }
  }
}

byId('channel').addEventListener('change', () => selectChannel(true));
byId('release').addEventListener('change', () => {
  currentRelease = releases.find(release => release.tag === byId('release').value) ?? null;
  renderRelease();
});
byId('format').addEventListener('change', renderAsset);
byId('copy-digest').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(byId('digest').textContent);
    byId('download-status').textContent = 'SHA‑256 скопирован';
  } catch (_) {
    byId('download-status').textContent = 'Выдели и скопируй SHA‑256 вручную';
  }
});

renderPlatform();
try {
  const response = await fetch('/v1/releases', {signal: AbortSignal.timeout(12000)});
  if (!response.ok) throw new Error('catalog unavailable');
  const catalog = await response.json();
  if (!Array.isArray(catalog.releases)) throw new Error('invalid catalog');
  releases = catalog.releases;
  stale = Boolean(catalog.stale);
  selectChannel(true);
  const latest = releases[0];
  if (latest) byId('hero-version').textContent = latest.name;
  if (detected) {
    const recommended = releases.find(release => assetsFor(release, detected).some(asset => safeDownload(asset.url)));
    const asset = assetsFor(recommended, detected).find(asset => safeDownload(asset.url));
    if (asset) {
      byId('hero-download').href = asset.url;
      byId('hero-download').textContent = `Скачать для ${labels[detected]} ↓`;
      byId('hero-caption').textContent = `${recommended.name} · ${formatSize(asset.size)}${detected === 'ios' ? ' · IPA требует подписи' : ''}`;
    }
  }
} catch (_) {
  byId('release-label').textContent = 'GitHub временно недоступен';
  byId('release').replaceChildren(new Option('Проверь выпуски на GitHub', ''));
  byId('download-status').textContent = 'Не удалось получить список версий. Загрузки доступны по ссылке ниже.';
}
