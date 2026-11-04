export function detectPlatform(userAgent = '', platform = '', touchPoints = 0) {
  if (/android/i.test(userAgent)) return 'android';
  if (/iphone|ipad|ipod/i.test(userAgent) || (/mac/i.test(platform) && touchPoints > 1)) return 'ios';
  if (/windows/i.test(userAgent)) return 'windows';
  if (/macintosh|mac os x/i.test(userAgent) || /mac/i.test(platform)) return 'macos';
  return null;
}

export function assetsFor(release, platform) {
  const assets = release?.assets ?? [];
  return assets.filter(asset => {
    if (/preview/i.test(asset.name) || !safeDownload(asset.url)) return false;
    return {
      android: /-promax-(?:universal|arm64-v8a|armeabi-v7a|x86_64)\.apk$/,
      ios: /-ios-unsigned\.ipa$/,
      windows: /(?:-Setup-[\d.-]+\.exe|-windows-x64\.zip)$/,
      macos: /-macos-universal\.zip$/,
    }[platform]?.test(asset.name);
  }).sort((a, b) => priority(a.name) - priority(b.name));
}

function priority(name) {
  if (name.includes('universal') || name.endsWith('.exe')) return 0;
  if (name.includes('arm64-v8a')) return 1;
  return 2;
}

export function assetLabel(asset) {
  if (asset.name.includes('universal')) return 'Универсальный APK · для всех архитектур';
  if (asset.name.includes('arm64-v8a')) return 'APK arm64 · большинство современных телефонов';
  if (asset.name.includes('armeabi-v7a')) return 'APK ARMv7 · старые 32-битные устройства';
  if (asset.name.includes('x86_64') && asset.name.endsWith('.apk')) return 'APK x86_64 · эмуляторы и совместимые устройства';
  if (asset.name.endsWith('.exe')) return 'Установщик Windows';
  if (asset.name.endsWith('-windows-x64.zip')) return 'Portable · без установщика';
  if (asset.name.endsWith('.ipa')) return 'IPA · требуется собственная подпись';
  if (asset.name.endsWith('-macos-universal.zip')) return 'macOS · Apple Silicon и Intel';
  return 'Архив';
}

export function chooseRelease(releases, channel, platform) {
  const filtered = releases.filter(release => channel === 'beta' ? release.beta : !release.beta);
  return filtered.find(release => assetsFor(release, platform).length > 0) ?? filtered[0] ?? null;
}

export function safeDownload(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && parsed.hostname === 'github.com' && !parsed.port && !parsed.username && !parsed.password && parsed.pathname.startsWith('/stillemptyNOW/ProMax/releases/download/') && !parsed.search && !parsed.hash;
  } catch (_) {
    return false;
  }
}

export function formatSize(size) {
  return `${(size / 1048576).toLocaleString('ru-RU', {maximumFractionDigits: 1})} МБ`;
}
