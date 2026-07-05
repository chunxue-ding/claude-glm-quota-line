'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('child_process');
const path = require('path');
const ns = require('../scripts/statusline');

const ROOT = path.join(__dirname, '..');
const SCRIPT = path.join(ROOT, 'scripts', 'statusline.js');
const NO_CFG = path.join(ROOT, 'tests', 'fixtures', '__no_such_config__.json');
const FIXTURE = (n) => path.join(ROOT, 'tests', 'fixtures', `${n}.json`);

function run(quota, config) {
  const env = { ...process.env, TZ: 'Asia/Shanghai', GLM_QUOTA_FIXTURE: FIXTURE(quota), GLM_QUOTA_CONFIG: config || NO_CFG };
  return execFileSync(process.execPath, [SCRIPT], { env, input: '{}', encoding: 'utf8' });
}

test('configValid rejects float barWidth, duplicate min, non-descending, missing last-0', () => {
  assert.strictEqual(ns.configValid({ barWidth: 5.5, levels: [{ min: 70, color: 'green' }, { min: 0, color: 'red' }] }), false);
  // NOTE: 10.0 is accepted, not rejected. In JS the literal 10.0 === 10 and
  // Number.isInteger(10) is true, so it is indistinguishable from an integer.
  // The bash version (jq `== floor`) accepts 10.0 too — this is parity, not a bug.
  assert.strictEqual(ns.configValid({ barWidth: 10.0, levels: [{ min: 70, color: 'green' }, { min: 0, color: 'red' }] }), true);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 70, color: 'green' }, { min: 70, color: 'red' }, { min: 0, color: 'red' }] }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 30, color: 'x' }, { min: 70, color: 'y' }, { min: 0, color: 'z' }] }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 70, color: 'green' }, { min: 30, color: 'orange' }] }), false); // last != 0
  assert.strictEqual(ns.configValid({ barWidth: 0, levels: ns.DEFAULT_LEVELS }), false);
  assert.strictEqual(ns.configValid({ barWidth: 21, levels: ns.DEFAULT_LEVELS }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: ns.DEFAULT_LEVELS }), true);
});

test('renderQuota routes boundaries correctly (>= inclusive) and unknown color -> gray', () => {
  const cfg = { barWidth: 10, levels: ns.DEFAULT_LEVELS };
  assert.ok(ns.renderQuota('5h', 30, '', cfg).includes('70% left'));       // used 30 -> remaining 70 -> green
  assert.ok(ns.renderQuota('5h', 31, '', cfg).includes('\x1b[38;5;214m')); // used 31 -> remaining 69 -> orange
  assert.ok(ns.renderQuota('5h', 10, '', cfg).includes('\x1b[32m'));       // used 10 -> remaining 90 -> green
  assert.ok(ns.renderQuota('5h', 'N/A', '', cfg).includes('N/A'));
  assert.ok(ns.renderQuota('5h', 0, '', cfg).includes('after use'));
  assert.ok(ns.renderQuota('5h', 5, '', { barWidth: 10, levels: [{ min: 0, color: 'nosuch' }] }).includes('\x1b[90m'));
});

test('green fixture renders default 10-cell green bars with reset times', () => {
  const out = run('green');
  assert.ok(out.includes('5h [████████░░] 80% left'));
  assert.ok(out.includes('week [█████████░] 90% left'));
  assert.ok(out.includes('reset 07-01 00:25'));
  assert.ok(out.includes('\x1b[32m'));
});

test('orange and red fixtures', () => {
  assert.ok(run('orange').includes('5h [█████░░░░░] 50% left'));
  assert.ok(run('orange').includes('\x1b[38;5;214m'));
  assert.ok(run('red').includes('5h [██░░░░░░░░] 20% left'));
  assert.ok(run('red').includes('\x1b[31m'));
});

test('no-week, fresh, null-percentage fixtures', () => {
  const nw = run('no-week');
  assert.ok(nw.includes('5h [██████░░░░] 65% left'));
  assert.ok(nw.includes('week [░░░░░░░░░░] N/A'));
  assert.ok(run('fresh').includes('5h [██████████] 100% left · reset after use'));
  assert.ok(run('null-percentage').includes('5h [░░░░░░░░░░] N/A'));
});

test('custom config drives width, colors, and 4 levels', () => {
  const out = run('green', FIXTURE('config-custom-width-color'));
  assert.ok(out.includes('5h [████░] 80% left'));
  assert.ok(out.includes('\x1b[36m')); // cyan
  const four = run('quota-mixed', FIXTURE('config-four-levels'));
  assert.ok(four.includes('5h [█████░░░░░] 55% left'));
  assert.ok(four.includes('\x1b[33m')); // yellow
  assert.ok(four.includes('week [████████░░] 85% left'));
  assert.ok(four.includes('\x1b[32m')); // green
});

test('invalid configs fall back to default', () => {
  // config-intfloat-barwidth (10.0) is intentionally NOT here: it is valid in
  // JS (10.0 === 10) and was valid in the bash version too.
  for (const c of ['config-invalid', 'config-float-barwidth', 'config-equal-min']) {
    const out = run('green', FIXTURE(c));
    assert.ok(out.includes('5h [████████░░] 80% left'), c);
    assert.ok(out.includes('\x1b[32m'), c);
  }
});
