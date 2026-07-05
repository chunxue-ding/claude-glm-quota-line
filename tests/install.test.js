'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');

function tmpHome() { return fs.mkdtempSync(path.join(os.tmpdir(), 'glm-install-')); }

test('install sets node statusLine, preserves other keys, removes legacy copy', () => {
  const home = tmpHome();
  const claude = path.join(home, '.claude');
  fs.mkdirSync(claude, { recursive: true });
  fs.writeFileSync(path.join(claude, 'settings.json'), JSON.stringify({ theme: 'dark', statusLine: { type: 'command', command: 'old' } }));
  fs.writeFileSync(path.join(claude, 'glm-usage-status.sh'), 'legacy');
  const env = { ...process.env, HOME: home, USERPROFILE: home };

  execFileSync(process.execPath, [path.join(ROOT, 'scripts', 'install.js')], { env, encoding: 'utf8' });

  const cfg = JSON.parse(fs.readFileSync(path.join(claude, 'settings.json'), 'utf8'));
  assert.strictEqual(cfg.theme, 'dark');
  assert.strictEqual(cfg.statusLine.command, 'node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"');
  assert.strictEqual(cfg.statusLine.refreshInterval, 60);
  assert.ok(!fs.existsSync(path.join(claude, 'glm-usage-status.sh')));
  fs.rmSync(home, { recursive: true, force: true });
});

test('uninstall removes statusLine (new or legacy forms), preserves config', () => {
  const cmds = [
    'node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"',
    '~/.claude/glm-usage-status.sh',
    '"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"',
  ];
  for (const cmd of cmds) {
    const home = tmpHome();
    const claude = path.join(home, '.claude');
    fs.mkdirSync(claude, { recursive: true });
    fs.writeFileSync(path.join(claude, 'settings.json'), JSON.stringify({ theme: 'dark', statusLine: { type: 'command', command: cmd } }));
    const env = { ...process.env, HOME: home, USERPROFILE: home };
    execFileSync(process.execPath, [path.join(ROOT, 'scripts', 'uninstall.js')], { env, encoding: 'utf8' });
    const cfg = JSON.parse(fs.readFileSync(path.join(claude, 'settings.json'), 'utf8'));
    assert.strictEqual(cfg.theme, 'dark');
    assert.ok(!cfg.statusLine, `should remove statusLine for ${cmd}`);
    fs.rmSync(home, { recursive: true, force: true });
  }
  // config preserved
  const home = tmpHome();
  const claude = path.join(home, '.claude');
  fs.mkdirSync(claude, { recursive: true });
  fs.writeFileSync(path.join(claude, 'glm-quota.json'), '{"barWidth":7}');
  const env = { ...process.env, HOME: home, USERPROFILE: home };
  execFileSync(process.execPath, [path.join(ROOT, 'scripts', 'uninstall.js')], { env, encoding: 'utf8' });
  assert.ok(fs.existsSync(path.join(claude, 'glm-quota.json')));
  fs.rmSync(home, { recursive: true, force: true });
});
