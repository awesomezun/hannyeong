import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../website/analytics.js', import.meta.url), 'utf8');
assert.ok(!source.includes('PENDING_'), 'real analytics IDs must be configured');
const key = 'hannyeong.analytics-consent';
function page(savedConsent) {
  const nodes = new Map();
  const node = (selector) => {
    if (!nodes.has(selector)) nodes.set(selector, {
      hidden: true, textContent: '', listeners: {},
      addEventListener(type, callback) { this.listeners[type] = callback; }
    });
    return nodes.get(selector);
  };
  const downloads = ['hero', 'install'].map(location => ({
    ...node(location), dataset: { downloadLocation: location },
    href: 'https://github.com/gityeop/hannyeong/releases/download/v0.4.0/Hannyeong-0.4.0-arm64.pkg',
    textContent: '다운로드 v0.4.0 ↓'
  }));
  const storage = new Map(savedConsent ? [[key, savedConsent]] : []);
  const scripts = [], expiredCookies = [], clarityCalls = [];
  const document = {
    querySelector: node, querySelectorAll: () => downloads,
    createElement: tag => ({ tag }), head: { append: script => scripts.push(script) }
  };
  Object.defineProperty(document, 'cookie', {
    get: () => '_ga=one; _ga_123=two; _clck=three; _clsk=four; preference=keep',
    set: value => expiredCookies.push(value)
  });
  let reloads = 0;
  const window = {};
  vm.runInNewContext(source, {
    document, window, Date,
    localStorage: { getItem: name => storage.get(name) ?? null, setItem: (name, value) => storage.set(name, value) },
    location: { hostname: 'hannyeong.app', reload: () => reloads++ }
  });
  return {
    node, window, storage, scripts, downloads, expiredCookies, clarityCalls,
    click: selector => node(selector).listeners.click(),
    events: () => window.dataLayer.filter(item => item.event === 'download_click'),
    reloads: () => reloads
  };
}

const fresh = page();
assert.equal(fresh.node('[data-analytics-consent]').hidden, false);
assert.equal(fresh.scripts.length, 0);
fresh.downloads[0].listeners.click();
assert.equal(fresh.events().length, 0, 'downloads before consent must not be recorded');
fresh.click('[data-analytics-decline]');
assert.equal(fresh.storage.get(key), 'denied');
assert.equal(fresh.scripts.length, 0);
assert.equal(fresh.reloads(), 0);
assert.equal(page('denied').scripts.length, 0, 'remembered refusal must block tags');

const accepted = page();
accepted.click('[data-analytics-accept]');
accepted.click('[data-analytics-accept]');
assert.equal(accepted.scripts.length, 1, 'consenting twice must not load GTM twice');
const commands = accepted.window.dataLayer.filter(item => item[0] === 'consent');
assert.equal(commands[0][2].analytics_storage, 'denied');
assert.equal(commands[0][2].ad_storage, 'denied');
assert.equal(commands[1][2].analytics_storage, 'granted');
for (const link of accepted.downloads) link.listeners.click();
assert.deepEqual(Array.from(accepted.events(), event => event.button_location), ['hero', 'install']);
assert.equal(page('granted').scripts.length, 1, 'remembered consent should load tags');
accepted.window.clarity = (...args) => accepted.clarityCalls.push(args);
accepted.click('[data-analytics-settings]');
accepted.click('[data-analytics-decline]');
assert.equal(accepted.storage.get(key), 'denied');
assert.equal(accepted.reloads(), 1, 'withdrawal must unload vendor scripts');
assert.ok(Object.entries(accepted.window).some(([name, value]) => name.startsWith('ga-disable-') && value === true));
assert.deepEqual(accepted.clarityCalls, [['stop']]);
assert.equal(accepted.expiredCookies.length, 8);
assert.ok(accepted.expiredCookies.every(cookie => !cookie.startsWith('preference=')));
accepted.downloads[0].listeners.click();
assert.equal(accepted.events().length, 2, 'downloads after withdrawal must not be recorded');
console.log('Analytics consent: initial/remembered refusal, consent, both download buttons, duplicate load and withdrawal passed.');
