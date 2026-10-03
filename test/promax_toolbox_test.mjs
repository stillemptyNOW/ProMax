import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const sent = [];
const notices = [];
const api = {
  chat: { sendText: async text => { sent.push(text); return String(sent.length); } },
  ui: { notify: async text => notices.push(text) },
};
const context = vm.createContext({ api });
const source = await readFile('assets/plugins/promax/main.js', 'utf8');
const module = new vm.SourceTextModule(source, { context });
const bridge = new vm.SyntheticModule(['chat', 'ui'], function () {
  this.setExport('chat', api.chat);
  this.setExport('ui', api.ui);
}, { context });
await module.link(async name => { assert.equal(name, 'komet:api'); return bridge; });
await module.evaluate();
await module.namespace.fix({ arguments: { text: 'Ghbdtn' } });
assert.equal(sent.pop(), 'Привет');
await module.namespace.fix({ arguments: { text: '' }, reply: { text: 'Руддщ' } });
assert.equal(sent.pop(), 'Hello');
await module.namespace.clean({ arguments: { text: 'synthetic\u200b   text\n\n\nnext' } });
assert.equal(sent.pop(), 'synthetic text\n\nnext');
await module.namespace.checklist({ arguments: { items: 'First | | Second' } });
assert.equal(sent.pop(), '☐ First\n☐ Second');
await module.namespace.choose({ arguments: { items: 'Alpha | Beta' } });
assert.ok(['Выбор: Alpha', 'Выбор: Beta'].includes(sent.pop()));
await module.namespace.choose({ arguments: { items: 'Only' } });
assert.equal(sent.length, 0);
assert.match(notices.pop(), /от 2 до 30/);
await module.namespace.fix({ arguments: {} });
assert.equal(sent.length, 0);
assert.match(notices.pop(), /Добавьте текст/);
console.log('ProMax Tools: 7 behavioral checks passed');
