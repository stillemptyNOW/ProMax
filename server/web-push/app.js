const stages = ['loading', 'install', 'unsupported', 'denied', 'permission', 'subscribe', 'link', 'failed'];
let registration;
let subscription;
function show(stage) {
  for (const name of stages) document.getElementById(name).hidden = name !== stage;
  document.getElementById('status').hidden = stage !== 'link';
}
function standalone() {
  return navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
}
function timeout(promise, milliseconds, message) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), milliseconds);
  })]).finally(() => clearTimeout(timer));
}
function failure(error) {
  document.getElementById('error-detail').textContent = `${error?.name || 'Ошибка'}: ${error?.message || 'Повторите с включённым интернетом.'}\nРазрешение: ${globalThis.Notification?.permission || 'недоступно'}\nС экрана «Домой»: ${standalone() ? 'да' : 'нет'}`;
  show('failed');
}
function displayReceipt(value) {
  const date = value?.receivedAt ? new Date(value.receivedAt) : null;
  document.getElementById('remote-status').textContent = date && Number.isFinite(date.getTime())
    ? `Удалённый push получен ${date.toLocaleString('ru-RU')}.`
    : 'Удалённая доставка ещё не проверена. Подтверждение регистрации смотрите в ProMax.';
}
async function loadReceipt() {
  if (!registration?.active) return;
  const channel = new MessageChannel();
  try {
    const response = new Promise(resolve => { channel.port1.onmessage = event => resolve(event.data); });
    registration.active.postMessage({type: 'get-receipt'}, [channel.port2]);
    displayReceipt(await timeout(response, 2000, 'Проверка доставки пока недоступна.'));
  } catch { displayReceipt(null); }
  finally { channel.port1.close(); channel.port2.close(); }
}
async function refresh() {
  if (!standalone()) return show('install');
  if (!('serviceWorker' in navigator) || !('PushManager' in globalThis) || !('Notification' in globalThis)) return show('unsupported');
  if (!registration) {
    await navigator.serviceWorker.register('/sw.js', {updateViaCache: 'none'});
    registration = await timeout(navigator.serviceWorker.ready, 15000, 'Не удалось запустить службу уведомлений. Проверьте интернет и откройте приложение заново.');
  }
  if (Notification.permission === 'denied') return show('denied');
  if (Notification.permission !== 'granted') return show('permission');
  subscription = await registration.pushManager.getSubscription();
  if (!subscription) return show('subscribe');
  document.getElementById('status-permission').textContent = 'Разрешено';
  document.getElementById('status-subscription').textContent = 'Создана';
  show('link');
  await loadReceipt();
}
async function safeRefresh() { try { await refresh(); } catch (error) { failure(error); } }
function button(id, action) {
  const element = document.getElementById(id);
  element.addEventListener('click', () => {
    element.disabled = true;
    try {
      Promise.resolve(action()).catch(failure).finally(() => element.disabled = false);
    } catch (error) { element.disabled = false; failure(error); }
  });
}
button('btn-permission', () => Notification.requestPermission().then(safeRefresh));
button('btn-subscribe', () => {
  if (!registration) throw new Error('Дождитесь проверки приложения и повторите.');
  return timeout(registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: ProMaxPush.keyBytes()}), 20000,
    'iPhone не создал подписку. Проверьте интернет, версию iOS и запуск с экрана «Домой».').then(safeRefresh);
});
button('btn-link', () => {
  if (!subscription) throw new Error('Сначала создайте подписку.');
  document.getElementById('link-result').textContent = 'Дождитесь подтверждения регистрации в ProMax. Если приложение не открылось, установите ProMax 1.0.2 или новее.';
  location.href = ProMaxPush.subscriptionLink(subscription);
});
button('btn-copy', async () => {
  if (!subscription) throw new Error('Сначала создайте подписку.');
  await navigator.clipboard.writeText(ProMaxPush.subscriptionLink(subscription));
  document.getElementById('link-result').textContent = 'Ссылка скопирована. Откройте её на этом iPhone с установленным ProMax.';
});
button('btn-test', async () => {
  await registration.showNotification('ProMax', {body: 'Проверка показа на этом iPhone. Доставка из MAX этим тестом не проверяется.', data: {url: '/'}});
  document.getElementById('test-result').textContent = 'Местное уведомление показано. Теперь проверьте настоящее сообщение с другого аккаунта.';
});
button('btn-relink', () => {
  if (subscription) location.href = ProMaxPush.subscriptionLink(subscription);
});
for (const id of ['btn-retry', 'btn-refresh-denied']) button(id, safeRefresh);
navigator.serviceWorker?.addEventListener('message', event => {
  if (event.data?.type === 'remote-push') displayReceipt(event.data);
  if (event.data?.type === 'subscription-changed') safeRefresh();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden) safeRefresh(); });
safeRefresh();
