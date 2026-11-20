importScripts('push-core.js');
const BASE_URL = new URL('.', self.location.href);
const SHELL_CACHE = 'promax-push-shell-v3';
const STATUS_CACHE = 'promax-push-status-v1';
const DIAGNOSTICS_CACHE = 'promax-push-diagnostics-v1';
const SHELL = ['', 'index.html', 'app.js', 'push-core.js', 'styles.css', 'manifest.webmanifest', 'icons/icon-1024.png', 'open.html', 'open.js'].map(path => new URL(path, BASE_URL).pathname);
const STATUS_URL = new URL('_push_receipt', BASE_URL).href;
const DIAGNOSTICS_URL = new URL('_push_diagnostics', BASE_URL).href;
const ICON_URL = new URL('icons/icon-1024.png', BASE_URL).pathname;

self.addEventListener('install', event => {
  event.waitUntil(caches.open(SHELL_CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys
    .filter(key => key.startsWith('promax-push-shell-') && key !== SHELL_CACHE)
    .map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || !SHELL.includes(url.pathname)) return;
  event.respondWith(fetch(event.request).catch(async () =>
    await caches.match(url.pathname) || new Response('Откройте приложение с интернетом.', {status: 503})));
});
async function receipt() {
  const response = await (await caches.open(STATUS_CACHE)).match(STATUS_URL);
  return response ? response.json() : null;
}
async function diagnosticsEnabled() {
  return Boolean(await (await caches.open(DIAGNOSTICS_CACHE)).match(DIAGNOSTICS_URL));
}
async function setDiagnostics(enabled) {
  const cache = await caches.open(DIAGNOSTICS_CACHE);
  if (enabled) await cache.put(DIAGNOSTICS_URL, new Response('1'));
  else await cache.delete(DIAGNOSTICS_URL);
  return enabled;
}
async function reportReceipt(outcome) {
  try {
    if (!await diagnosticsEnabled()) return;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    try {
      await fetch(new URL('/v1/telemetry/operations', BASE_URL), {
        method: 'POST', headers: {'Content-Type': 'application/json'},
        credentials: 'omit', redirect: 'error', signal: controller.signal,
        body: JSON.stringify({events: [{stage: 'webPushReceipt', outcome, platform: 'web', version: 'unknown'}]}),
      });
    } finally { clearTimeout(timer); }
  } catch {}
}
async function receivePush(event) {
  const payload = ProMaxPush.notificationPayload(event.data);
  try {
    await self.registration.showNotification(payload.title, {
      body: payload.body, icon: ICON_URL, badge: ICON_URL,
      data: {url: payload.url},
    });
  } catch (error) {
    await reportReceipt('failed');
    throw error;
  }
  try {
    const value = {receivedAt: new Date().toISOString()};
    await (await caches.open(STATUS_CACHE)).put(STATUS_URL, new Response(JSON.stringify(value)));
    const clients = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of clients) client.postMessage({type: 'remote-push', ...value});
  } catch {}
  await reportReceipt('success');
}
self.addEventListener('push', event => event.waitUntil(receivePush(event)));
self.addEventListener('message', event => {
  const port = event.ports?.[0];
  if (!port) return;
  let reply;
  if (event.data?.type === 'get-receipt') reply = receipt();
  if (event.data?.type === 'get-diagnostics') reply = diagnosticsEnabled();
  if (event.data?.type === 'set-diagnostics' && typeof event.data.enabled === 'boolean') {
    reply = setDiagnostics(event.data.enabled);
  }
  if (reply) event.waitUntil(reply.then(value => port.postMessage(value), () => port.postMessage(null)));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const link = ProMaxPush.openLink(event.notification.data?.url);
  event.waitUntil(self.clients.openWindow(new URL(`open.html?to=${encodeURIComponent(link)}`, BASE_URL).href));
});
self.addEventListener('pushsubscriptionchange', event => {
  event.waitUntil((async () => {
    try { await caches.delete(STATUS_CACHE); } catch {}
    try { await self.registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: ProMaxPush.keyBytes()}); } catch {}
    await self.registration.showNotification('ProMax', {body: 'Подписка изменилась. Откройте ProMax Уведомления и свяжите её с ProMax заново.', data: {url: '/'}});
    for (const client of await self.clients.matchAll({type: 'window', includeUncontrolled: true})) {
      client.postMessage({type: 'subscription-changed'});
    }
  })());
});
