import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync('server/promax-hub/settings-link.js', 'utf8');

function run(hash, copyFails = false) {
  const elements = new Map(['open', 'copy', 'status'].map(id => [id, {
    hidden: true,
    textContent: '',
    listeners: {},
    addEventListener(name, handler) { this.listeners[name] = handler; },
  }]));
  const copied = [];
  vm.runInNewContext(script, {
    location: {hash, href: 'https://boriskino.qd.je/settings' + hash},
    document: {getElementById: id => elements.get(id)},
    navigator: {clipboard: {async writeText(value) {
      if (copyFails) throw new Error('synthetic clipboard denial');
      copied.push(value);
    }}},
  });
  return {elements, copied};
}

const valid = run('#v1.c3ludGhldGlj');
assert.equal(valid.elements.get('open').href, 'promax://settings#v1.c3ludGhldGlj');
assert.equal(valid.elements.get('open').hidden, false);
await valid.elements.get('copy').listeners.click();
assert.deepEqual(valid.copied, ['https://proma-x.xyz/settings#v1.c3ludGhldGlj']);

for (const hash of ['', '#v2.synthetic', '#v1.<script>', '#v1.' + 'a'.repeat(16384)]) {
  const invalid = run(hash);
  assert.equal(invalid.elements.get('open').hidden, true);
  assert.equal(invalid.elements.get('copy').hidden, true);
  assert.notEqual(invalid.elements.get('status').textContent, '');
}

const denied = run('#v1.c3ludGhldGlj', true);
await denied.elements.get('copy').listeners.click();
assert.equal(denied.copied.length, 0);
assert.notEqual(denied.elements.get('status').textContent, '');
console.log('Settings landing: open, copy, invalid input and denied clipboard passed');
