import assert from 'node:assert/strict';
import {assetsFor, chooseRelease, detectPlatform, safeDownload} from '../server/promax-hub/site/release-utils.mjs';
import {recordDownload} from '../server/promax-hub/site/download-counter.mjs';

const base = 'https://github.com/stillemptyNOW/ProMax/releases/download/synthetic/';
const apk = {name: 'ProMax-0.0.0-promax-universal.apk', url: base + 'synthetic.apk'};
const latest = {tag: 'synthetic-new', beta: true, assets: [{name: 'ProMax-ios-unsigned.ipa', url: base + 'synthetic.ipa'}]};
const previous = {tag: 'synthetic-old', beta: true, assets: [apk, {name: 'ProMax-0.0.0-preview-universal.apk', url: base + 'debug.apk'}]};
assert.equal(chooseRelease([latest, previous], 'beta', 'android'), previous);
assert.equal(chooseRelease([latest, previous], 'beta', 'ios'), latest);
assert.equal(chooseRelease([latest, previous], 'stable', 'android'), null);
const unsafe = {tag: 'synthetic-unsafe', beta: true, assets: [{...apk, url: 'https://synthetic.example/untrusted.apk'}]};
assert.equal(chooseRelease([unsafe, previous], 'beta', 'android'), previous);
assert.deepEqual(assetsFor(unsafe, 'android'), []);
assert.deepEqual(assetsFor(previous, 'android'), [apk]);
assert.equal(detectPlatform('Mozilla Android', '', 0), 'android');
assert.equal(detectPlatform('Mozilla Windows NT', '', 0), 'windows');
assert.equal(detectPlatform('Mozilla Macintosh', 'MacIntel', 5), 'ios');
assert.equal(detectPlatform('Mozilla Macintosh', 'MacIntel', 0), 'macos');
const mac = {name: 'ProMax-macos-universal.zip', url: base + 'synthetic.zip'};
assert.deepEqual(assetsFor({assets: [mac, apk]}, 'macos'), [mac]);
assert.equal(safeDownload(base + 'synthetic.apk'), true);
for (const url of ['javascript:alert(1)', 'https://github.com.synthetic.example/file', 'https://synthetic@github.com/stillemptyNOW/ProMax/releases/download/file', base + 'file?redirect=synthetic']) {
  assert.equal(safeDownload(url), false);
}
console.log('Downloads: platform, incomplete release fallback, channels, preview exclusion and URL checks passed');
let recorded;
assert.equal(await recordDownload(mac.url, 'a'.repeat(32), async (url, options) => {
  recorded = {url, ...options};
  return {ok: true, json: async () => ({started: 2})};
}), 2);
assert.equal(recorded.url, '/v1/downloads');
assert.equal(recorded.keepalive, true);
assert.deepEqual(JSON.parse(recorded.body), {asset: mac.url, event: 'a'.repeat(32)});
await assert.rejects(recordDownload(mac.url, 'a'.repeat(32), async () => ({ok: false})));
