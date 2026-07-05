'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { shouldRefresh, saveCache } = require('../scripts/statusline');

test('saveCache writes file with 0o600 on POSIX', () => {
  const f = path.join(os.tmpdir(), `glm-cache-test-${process.pid}.json`);
  saveCache(f, '{"data":{}}');
  try {
    assert.ok(fs.existsSync(f));
    if (process.platform !== 'win32') {
      assert.strictEqual(fs.statSync(f).mode & 0o777, 0o600);
    }
  } finally { try { fs.unlinkSync(f); } catch (_) {} }
});

test('shouldRefresh: missing -> true, fresh -> false, stale -> true', () => {
  const f = path.join(os.tmpdir(), `glm-refresh-test-${process.pid}.json`);
  try { fs.unlinkSync(f); } catch (_) {}
  assert.strictEqual(shouldRefresh(f, 55000), true);
  fs.writeFileSync(f, 'x');
  try {
    assert.strictEqual(shouldRefresh(f, 55000), false);
    const old = new Date(Date.now() - 60000);
    fs.utimesSync(f, old, old);
    assert.strictEqual(shouldRefresh(f, 55000), true);
  } finally { try { fs.unlinkSync(f); } catch (_) {} }
});
