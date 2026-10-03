(() => {
  const VAPID_KEY = 'BAlrEY3NvC8TgHWYfNRY3LZOtrPh8fVtz5eSNqMtN-UNI75jrLjBIAFXqrk87V9FNMVkMqgDtRXlyzvvErmj-8Q';
  function keyBytes() {
    const raw = atob(VAPID_KEY.replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(raw, c => c.charCodeAt(0));
  }
  function subscriptionLink(subscription) {
    const {endpoint, keys} = subscription.toJSON();
    if (!endpoint || !keys?.p256dh || !keys?.auth) throw new Error('Подписка iPhone неполная. Создайте её заново.');
    const url = new URL(endpoint);
    if (url.protocol !== 'https:') throw new Error('Адрес подписки должен использовать HTTPS.');
    return `promax://webpush?${new URLSearchParams({endpoint, p256dh: keys.p256dh, auth: keys.auth})}`;
  }
  function openLink(input) {
    let path = '/';
    try { path = new URL(typeof input === 'string' ? input : '/', 'https://web.max.ru').pathname; } catch {}
    let match = path.match(/^\/inbound-call\/(\d{1,18})\/[^/]+\/?$/);
    if (match) return `promax://open?callerId=${match[1]}`;
    match = path.match(/^\/messages\/c(-?\d{1,18})\/?$/);
    if (match) return `promax://open?chatId=-${match[1].replace(/^-/, '')}`;
    match = path.match(/^\/messages\/(-\d{1,18})\/?$/);
    if (match) return `promax://open?chatId=${match[1]}`;
    match = path.match(/^\/messages\/(\d{1,18})\/?$/);
    if (match) return `promax://open?userId=${match[1]}`;
    return 'promax://open';
  }
  function notificationPayload(data) {
    let payload;
    try { payload = data?.json(); } catch {}
    const object = payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : {};
    const notice = object.notification && typeof object.notification === 'object' ? object.notification : object;
    return {
      title: typeof notice.title === 'string' && notice.title.trim() ? notice.title.slice(0, 150) : 'ProMax',
      body: typeof notice.body === 'string' && notice.body.trim() ? notice.body.slice(0, 500) : 'Новое сообщение в MAX',
      url: typeof object.url === 'string' ? object.url : typeof notice.url === 'string' ? notice.url : '/',
    };
  }
  globalThis.ProMaxPush = {VAPID_KEY, keyBytes, subscriptionLink, openLink, notificationPayload};
})();
