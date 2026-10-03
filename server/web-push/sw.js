importScripts('/push-core.js');
const SHELL_CACHE = 'promax-push-shell-v1';
const STATUS_CACHE = 'promax-push-status-v1';
const SHELL = ['/', '/index.html', '/app.js', '/push-core.js', '/styles.css', '/manifest.webmanifest', '/icons/icon-1024.png', '/open.html', '/open.js'];
const STATUS_URL = new URL('/_push_receipt', self.location.origin).href;

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
async function receivePush(event) {
  const payload = ProMaxPush.notificationPayload(event.data);
  await self.registration.showNotification(payload.title, {
    body: payload.body, icon: '/icons/icon-1024.png', badge: '/icons/icon-1024.png',
    data: {url: payload.url},
  });
  try {
    const value = {receivedAt: new Date().toISOString()};
    await (await caches.open(STATUS_CACHE)).put(STATUS_URL, new Response(JSON.stringify(value)));
    const clients = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of clients) client.postMessage({type: 'remote-push', ...value});
  } catch {}
}
self.addEventListener('push', event => event.waitUntil(receivePush(event)));
self.addEventListener('message', event => {
  if (event.data?.type === 'get-receipt' && event.ports?.[0]) {
    event.waitUntil(receipt().then(value => event.ports[0].postMessage(value)).catch(() => event.ports[0].postMessage(null)));
  }
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const link = ProMaxPush.openLink(event.notification.data?.url);
  event.waitUntil(self.clients.openWindow(`/open.html?to=${encodeURIComponent(link)}`));
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
