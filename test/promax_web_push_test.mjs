import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const root = resolve('server/web-push');
const core = readFileSync(resolve(root, 'push-core.js'), 'utf8');
function context(extra = {}) {
  const value = vm.createContext({URL, URLSearchParams, Uint8Array, atob, Response, setTimeout, clearTimeout, ...extra});
  vm.runInContext(core, value);
  return value;
}
test('MAX VAPID key is a 65-byte uncompressed P-256 public key', () => {
  const bytes = context().ProMaxPush.keyBytes();
  assert.equal(bytes.length, 65);
  assert.equal(bytes[0], 4);
});
test('subscription links use the ProMax scheme and preserve escaped keys', () => {
  const value = {endpoint: 'https://web.push.apple.com/synthetic?x=1&y=2', keys: {p256dh: 'synthetic-public', auth: 'synthetic-auth'}};
  const link = new URL(context().ProMaxPush.subscriptionLink({toJSON: () => value}));
  assert.equal(link.protocol, 'promax:');
  assert.equal(link.hostname, 'webpush');
  assert.equal(link.searchParams.get('endpoint'), value.endpoint);
  assert.equal(link.searchParams.get('auth'), value.keys.auth);
});
test('notification routes preserve group, user and incoming call targets', () => {
  const {openLink} = context().ProMaxPush;
  assert.equal(openLink('/messages/c101'), 'promax://open?chatId=-101');
  assert.equal(openLink('/messages/-101'), 'promax://open?chatId=-101');
  assert.equal(openLink('https://web.max.ru/messages/202'), 'promax://open?userId=202');
  assert.equal(openLink('/inbound-call/303/synthetic'), 'promax://open?callerId=303');
  assert.equal(openLink('javascript:alert(1)'), 'promax://open');
});
function worker() {
  const handlers = new Map();
  const stores = new Map();
  const notifications = [];
  const opened = [];
  const caches = {
    async open(name) {
      if (!stores.has(name)) stores.set(name, new Map());
      const store = stores.get(name);
      return {async addAll() {}, async match(key) {return store.get(key)?.clone();},
        async put(key, value) {store.set(key, value.clone());}};
    },
    async keys() {return [...stores.keys()];},
    async delete(name) {return stores.delete(name);},
  };
  const self = {location: {origin: 'https://push.example.test'},
    registration: {async showNotification(title, options) {notifications.push({title, options});},
      pushManager: {async subscribe() {throw new Error('Synthetic subscription failure');}}},
    clients: {async matchAll() {return [];}, async openWindow(url) {opened.push(url);}, async claim() {}},
    addEventListener(name, action) {handlers.set(name, action);}, async skipWaiting() {}};
  const value = context({self, caches, importScripts() {}});
  vm.runInContext(readFileSync(resolve(root, 'sw.js'), 'utf8'), value);
  async function dispatch(name, extra = {}) {
    let work;
    handlers.get(name)({waitUntil(promise) {work = promise;}, ...extra});
    await work;
  }
  return {dispatch, notifications, stores, opened};
}
test('a malformed remote payload still produces a visible notification and a receipt', async () => {
  const value = worker();
  await value.dispatch('push', {data: {json() {throw new Error('Synthetic malformed payload');}}});
  assert.equal(value.notifications.length, 1);
  assert.equal(value.notifications[0].title, 'ProMax');
  const receipt = await [...value.stores.get('promax-push-status-v1').values()][0].json();
  assert.ok(Number.isFinite(Date.parse(receipt.receivedAt)));
  assert.deepEqual(Object.keys(receipt), ['receivedAt']);
});
test('remote title and body are displayed without persisting message text', async () => {
  const value = worker();
  await value.dispatch('push', {data: {json: () => ({title: 'Synthetic sender', body: 'Synthetic private text', url: '/messages/c101'})}});
  assert.equal(value.notifications[0].options.body, 'Synthetic private text');
  const receipt = await [...value.stores.get('promax-push-status-v1').values()][0].text();
  assert.ok(!receipt.includes('Synthetic private text'));
});
test('notification clicks open a same-origin page with a generated native target', async () => {
  const value = worker();
  await value.dispatch('notificationclick', {notification: {close() {}, data: {url: '/messages/202'}}});
  const opened = new URL(value.opened[0], 'https://push.example.test');
  assert.equal(opened.origin, 'https://push.example.test');
  assert.equal(opened.searchParams.get('to'), 'promax://open?userId=202');
});
test('a subscription change clears old receipt and requests relinking even when renewal fails', async () => {
  const value = worker();
  await value.dispatch('push');
  await value.dispatch('pushsubscriptionchange');
  assert.ok(!value.stores.has('promax-push-status-v1'));
  assert.match(value.notifications.at(-1).options.body, /заново/);
});
test('opening ProMax and a local test never claim a remote push was received', async () => {
  const elements = new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id, {hidden: true, textContent: '', handlers: {},
      addEventListener(name, action) {this.handlers[name] = action;}});
    return elements.get(id);
  }
  const local = [];
  class Channel {
    constructor() {
      this.port1 = {close() {}, onmessage: null};
      this.port2 = {close() {}, postMessage: data => this.port1.onmessage?.({data})};
    }
  }
  const subscription = {toJSON: () => ({endpoint: 'https://web.push.apple.com/synthetic', keys: {p256dh: 'synthetic-public', auth: 'synthetic-auth'}})};
  const registration = {active: {postMessage(_, ports) {ports[0].postMessage(null);}},
    pushManager: {async getSubscription() {return subscription;}},
    async showNotification(title, options) {local.push({title, options});}};
  const location = {href: 'https://push.example.test'};
  const value = context({MessageChannel: Channel, location,
    Notification: {permission: 'granted'}, matchMedia: () => ({matches: true}),
    navigator: {standalone: true, serviceWorker: {async register() {return registration;}, ready: Promise.resolve(registration), addEventListener() {}}},
    PushManager: {}, document: {getElementById: element, addEventListener() {}}});
  vm.runInContext(readFileSync(resolve(root, 'app.js'), 'utf8'), value);
  await value.safeRefresh();
  element('btn-link').handlers.click();
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.match(location.href, /^promax:\/\/webpush\?/);
  assert.equal(element('link').hidden, false);
  assert.match(element('remote-status').textContent, /ещё не проверена/);
  element('btn-test').handlers.click();
  await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(local.length, 1);
  assert.match(local[0].options.body, /не проверяется/);
  assert.match(element('remote-status').textContent, /ещё не проверена/);
});
