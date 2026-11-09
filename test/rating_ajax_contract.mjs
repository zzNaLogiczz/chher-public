// Run with: node test/rating_ajax_contract.mjs
// Execute the production WebView script with a local fake fetch; no network.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(
  new URL('../lib/network/webview_fetcher.dart', import.meta.url), 'utf8',
);
const body = source.split('Future<ChhResponse> _ajaxRequest')[1]
  ?.match(/functionBody: r"""([\s\S]*?)"""/)?.[1];
assert.ok(body, 'Production AJAX request script must be found');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const request = new AsyncFunction('url', 'fields', 'fetch', body);
const url = 'https://www.chiphell.com/forum.php';
const fields = { referer: `${url}?mod=misc&action=rate`, score1: '1', reason: '测试理由' };

for (const form of [null, fields]) {
  let calls = 0;
  const result = await request(url, form, async (_, options) => {
    calls++;
    assert.equal(options.method, form ? 'POST' : 'GET');
    assert.equal(options.redirect, form ? 'error' : 'follow');
    assert.equal(options.credentials, 'include');
    assert.equal(options.headers['X-Requested-With'], 'XMLHttpRequest');
    if (form) assert.equal(new URLSearchParams(options.body).get('reason'), '测试理由');
    else assert.equal(options.body, undefined);
    return { status: 200, text: async () => '<root>local fixture</root>' };
  });
  assert.equal(calls, 1);
  assert.equal(result.status, 200);
}

for (const status of [307, 308]) {
  let submissions = 0;
  const result = await request(url, fields, async (_, options) => {
    submissions++;
    // Model browser fetch: redirect:error rejects instead of resubmitting POST.
    if (options.redirect === 'error') throw new TypeError(`HTTP ${status} redirect`);
    if (options.redirect === 'follow') submissions++;
    return { status: 200, text: async () => 'unexpected replay' };
  });
  assert.equal(submissions, 1, `HTTP ${status} must never replay the rating`);
  assert.equal(result.status, -1, 'Redirect rejection must remain an uncertain result');
  assert.equal(result.text, '');
}

console.log('Rating WebView AJAX contract passed: GET follows; POST rejects 307/308 without replay.');
