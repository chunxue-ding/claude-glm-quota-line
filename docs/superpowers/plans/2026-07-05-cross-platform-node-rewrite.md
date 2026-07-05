# Cross-Platform Node Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the claude-glm-quota-line plugin's scripts in Node.js so the status line and installer run with zero external dependencies on Windows, macOS, and Linux (today they require bash + jq, which breaks on Windows where Git Bash lacks jq).

**Architecture:** Replace `scripts/{statusline,install,uninstall}.sh` with `.js` equivalents using only Node builtins (`https`, `fs`, `path`, `os`). `statusLine.command` becomes `node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"`. Tests migrate from bash to `node:test` so they run on Windows too. No bash fallback — Claude Code is a Node app, so Node is always present.

**Tech Stack:** Node.js (builtins only — no npm dependencies). `node:test` for tests.

**Spec:** `docs/superpowers/specs/2026-07-05-cross-platform-node-rewrite-design.md`

## Global Constraints

- Node.js only; NO external dependencies. Use only builtins: `https`, `fs`, `path`, `os`, `node:test`, `node:assert`, `child_process`.
- The status line must NEVER crash the Claude Code prompt — wrap all parsing; any error → a safe fallback string and exit 0.
- Config format unchanged: `{"barWidth": int 1–20, "levels": [{"min": int 0–100, "color": name}]}`, levels strictly descending, last level's `min == 0`. Colors: `green, orange, red, yellow, blue, cyan, magenta, gray, white` (unknown → `gray`).
- Invalid/absent config → built-in default (green ≥70, orange 30–69, red <30, barWidth 10).
- Env vars: `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `GLM_QUOTA_CONFIG` (config path override), `GLM_QUOTA_FIXTURE` (quota-data override for tests).
- Cross-platform: Windows (Git Bash), macOS, Linux. `fs.chmodSync(file, 0o600)` on POSIX; on Windows it is a safe no-op (do not assert perms there).
- `statusLine.command` exact value: `node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"`.
- Tests run via `node --test tests/`. Reuse `tests/fixtures/*.json` unchanged.
- Never write or log `ANTHROPIC_AUTH_TOKEN`.
- Each task ends with `node --test tests/` green and a commit.

---

### Task 1: Verify Node runs the status line on Windows (manual gate)

**Why:** The whole rewrite assumes `node` is on the PATH that Claude Code uses to run `statusLine.command` on Windows (Git Bash). Confirm in a real Windows + Claude Code session before the Node work lands. If `node` is NOT found there, stop and reconsider (bash fallback or bundled runtime).

This task is performed by a human on Windows, after Task 2 is merged (it needs `statusline.js` to exist). No code commit.

- [ ] **Step 1: On Windows, after Task 2 is merged, set a probe statusLine**

Back up `%USERPROFILE%\.claude\settings.json`, then set:

```json
{ "statusLine": { "type": "command", "command": "node -e \"process.stdout.write(process.version)\"", "refreshInterval": 60 } }
```

- [ ] **Step 2: Restart Claude Code and read the status line**

- Shows a Node version (e.g. `v20.11.1`) → Node is reachable. Proceed; the rewrite is valid on Windows.
- Shows an error / `node: command not found` → Node is NOT on the status-line PATH. Stop; report back. Do not ship the Node-only install for Windows without a fallback.

- [ ] **Step 3: Restore settings**

Restore the backed-up `settings.json`.

---

### Task 2: Create `statusline.js` with config-driven rendering, fetch, and cache

**Files:**
- Create: `scripts/statusline.js`
- Create: `tests/statusline.test.js`
- Create: `tests/cache.test.js`
- Reuse: `tests/fixtures/*.json` (do not modify)

**Interfaces:**
- Consumes: env `GLM_QUOTA_FIXTURE`, `GLM_QUOTA_CONFIG`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`; fixtures in `tests/fixtures/`.
- Produces: `scripts/statusline.js` runnable as `node scripts/statusline.js`, exporting pure helpers for tests.

- [ ] **Step 1: Create `scripts/statusline.js`**

```javascript
#!/usr/bin/env node
'use strict';

const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const GRAY = '\x1b[90m';

const DEFAULT_LEVELS = [
  { min: 70, color: 'green' },
  { min: 30, color: 'orange' },
  { min: 0, color: 'red' },
];
const DEFAULT_BAR_WIDTH = 10;
const COLOR_ANSI = {
  green: '\x1b[32m', orange: '\x1b[38;5;214m', red: '\x1b[31m',
  yellow: '\x1b[33m', blue: '\x1b[34m', cyan: '\x1b[36m',
  magenta: '\x1b[35m', gray: '\x1b[90m', white: '\x1b[37m',
};

function colorAnsi(name) { return COLOR_ANSI[name] || COLOR_ANSI.gray; }
function isInt(n) { return typeof n === 'number' && Number.isInteger(n); }

function configValid(cfg) {
  if (!cfg || typeof cfg !== 'object') return false;
  if (!isInt(cfg.barWidth) || cfg.barWidth < 1 || cfg.barWidth > 20) return false;
  const levels = cfg.levels;
  if (!Array.isArray(levels) || levels.length === 0) return false;
  for (const lv of levels) {
    if (!lv || !isInt(lv.min) || lv.min < 0 || lv.min > 100) return false;
    if (typeof lv.color !== 'string') return false;
  }
  for (let i = 0; i < levels.length - 1; i++) {
    if (!(levels[i].min > levels[i + 1].min)) return false; // strictly descending
  }
  if (levels[levels.length - 1].min !== 0) return false;
  return true;
}

function loadConfig() {
  const file = process.env.GLM_QUOTA_CONFIG ||
    path.join(os.homedir(), '.claude', 'glm-quota.json');
  try {
    if (fs.existsSync(file)) {
      const cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (configValid(cfg)) return cfg;
    }
  } catch (_) { /* fall through */ }
  return { barWidth: DEFAULT_BAR_WIDTH, levels: DEFAULT_LEVELS };
}

function extractFields(quotaJson) {
  const limits = (quotaJson && quotaJson.data && Array.isArray(quotaJson.data.limits))
    ? quotaJson.data.limits : [];
  const find = (unit) => limits.find((lv) => lv && lv.type === 'TOKENS_LIMIT' && lv.unit === unit) || {};
  const f = find(3);
  const w = find(6);
  const pct = (x) => (x.percentage === null || x.percentage === undefined) ? 'N/A' : x.percentage;
  return { fiveH: pct(f), week: pct(w), fiveReset: f.nextResetTime || '', weekReset: w.nextResetTime || '' };
}

function renderQuota(label, used, resetMs, cfg) {
  const width = cfg.barWidth;
  if (used === 'N/A') {
    return `${GRAY}${label} [${'░'.repeat(width)}] N/A${RESET}`;
  }
  const usedInt = Math.round(Number(used));
  let remaining = 100 - usedInt;
  if (remaining < 0) remaining = 0;
  if (remaining > 100) remaining = 100;
  const level = cfg.levels.find((lv) => remaining >= lv.min) || { color: 'gray' };
  const color = colorAnsi(level.color);
  const filled = Math.floor((remaining * width) / 100);
  const bar = '█'.repeat(filled) + '░'.repeat(width - filled);
  let resetDisplay = 'N/A';
  if (resetMs && resetMs !== 'null') {
    const d = new Date(Number(resetMs));
    const pad = (n) => String(n).padStart(2, '0');
    resetDisplay = `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } else if (usedInt === 0) {
    resetDisplay = 'after use';
  }
  return `${color}${label} [${bar}] ${remaining}% left · reset ${resetDisplay}${RESET}`;
}

function cachePath() {
  return path.join(os.tmpdir(), `glm-coding-plan-quota-${os.userInfo().username || 'user'}.json`);
}

function shouldRefresh(file, maxAgeMs) {
  try {
    const st = fs.statSync(file);
    return (Date.now() - st.mtimeMs) >= maxAgeMs;
  } catch (_) { return true; }
}

function saveCache(file, body) {
  fs.writeFileSync(file, body, { mode: 0o600 });
  try { fs.chmodSync(file, 0o600); } catch (_) { /* Windows: no-op */ }
}

function fetchQuota(baseDomain, token) {
  return new Promise((resolve, reject) => {
    const req = https.request(`${baseDomain}/api/monitor/usage/quota/limit`, {
      headers: { Authorization: token, 'Accept-Language': 'zh-CN', 'Content-Type': 'application/json' },
      timeout: 5000,
    }, (res) => { let data = ''; res.on('data', (c) => (data += c)); res.on('end', () => resolve(data)); });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.end();
  });
}

function drainStdin() {
  return new Promise((resolve) => {
    let done = false;
    const fin = () => { if (!done) { done = true; resolve(); } };
    process.stdin.on('end', fin);
    process.stdin.on('error', fin);
    process.stdin.on('close', fin);
    process.stdin.resume();
    setTimeout(fin, 200);
  });
}

async function main() {
  await drainStdin();
  const cfg = loadConfig();
  let source = null;

  if (process.env.GLM_QUOTA_FIXTURE) {
    try { source = JSON.parse(fs.readFileSync(process.env.GLM_QUOTA_FIXTURE, 'utf8')); }
    catch (_) { source = null; }
  } else {
    const token = process.env.ANTHROPIC_AUTH_TOKEN || '';
    const baseUrl = process.env.ANTHROPIC_BASE_URL || 'https://open.bigmodel.cn/api/anthropic';
    const m = baseUrl.match(/^https?:\/\/[^/]+/);
    const baseDomain = m ? m[0] : 'https://open.bigmodel.cn';
    const cache = cachePath();
    if (token && shouldRefresh(cache, 55000)) {
      try {
        const body = await fetchQuota(baseDomain, token);
        const parsed = JSON.parse(body);
        if (parsed && parsed.data && Array.isArray(parsed.data.limits)) saveCache(cache, body);
      } catch (_) { /* use cache */ }
    }
    try { source = JSON.parse(fs.readFileSync(cache, 'utf8')); } catch (_) { source = null; }
    if (!source) {
      process.stdout.write(token ? `${GRAY}GLM quota: unavailable${RESET}` : `${GRAY}GLM quota: no token${RESET}`);
      return;
    }
  }

  if (!source) { process.stdout.write(`${GRAY}GLM quota: unavailable${RESET}`); return; }
  const { fiveH, week, fiveReset, weekReset } = extractFields(source);
  process.stdout.write(
    `${BOLD}GLM${RESET} ${renderQuota('5h', fiveH, fiveReset, cfg)}  ${renderQuota('week', week, weekReset, cfg)}`
  );
}

if (require.main === module) {
  main().catch(() => process.stdout.write(`${GRAY}GLM quota: unavailable${RESET}`));
}

module.exports = { configValid, loadConfig, extractFields, renderQuota, shouldRefresh, saveCache, cachePath, DEFAULT_LEVELS, DEFAULT_BAR_WIDTH };
```

- [ ] **Step 2: Create `tests/statusline.test.js`**

```javascript
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
  assert.strictEqual(ns.configValid({ barWidth: 10.0, levels: [{ min: 70, color: 'green' }, { min: 0, color: 'red' }] }), false); // float type
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 70, color: 'green' }, { min: 70, color: 'red' }, { min: 0, color: 'red' }] }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 30, color: 'x' }, { min: 70, color: 'y' }, { min: 0, color: 'z' }] }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: [{ min: 70, color: 'green' }, { min: 30, color: 'orange' }] }), false); // last != 0
  assert.strictEqual(ns.configValid({ barWidth: 0, levels: ns.DEFAULT_LEVELS }), false);
  assert.strictEqual(ns.configValid({ barWidth: 21, levels: ns.DEFAULT_LEVELS }), false);
  assert.strictEqual(ns.configValid({ barWidth: 10, levels: ns.DEFAULT_LEVELS }), true);
});

test('renderQuota routes boundaries correctly (>= inclusive) and unknown color -> gray', () => {
  const cfg = { barWidth: 10, levels: ns.DEFAULT_LEVELS };
  assert.ok(ns.renderQuota('5h', 30, '', cfg).includes('70% left'));       // remaining 70 -> green
  assert.ok(ns.renderQuota('5h', 31, '', cfg).includes('\x1b[38;5;214m')); // remaining 69 -> orange
  assert.ok(ns.renderQuota('5h', 80, '', cfg).includes('\x1b[32m'));       // green
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
  for (const c of ['config-invalid', 'config-float-barwidth', 'config-equal-min', 'config-intfloat-barwidth']) {
    const out = run('green', FIXTURE(c));
    assert.ok(out.includes('5h [████████░░] 80% left'), c);
    assert.ok(out.includes('\x1b[32m'), c);
  }
});
```

- [ ] **Step 3: Create `tests/cache.test.js`**

```javascript
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
```

- [ ] **Step 4: Run the tests**

Run: `node --test tests/`
Expected: all PASS (statusline + cache). No stderr noise. Also `node --check scripts/statusline.js` clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/statusline.js tests/statusline.test.js tests/cache.test.js
git commit -m "feat: rewrite statusline in Node for cross-platform (no jq) support"
```

---

### Task 3: Create `install.js` / `uninstall.js` and point commands at Node

**Files:**
- Create: `scripts/install.js`
- Create: `scripts/uninstall.js`
- Modify: `commands/setup.md`
- Modify: `commands/usage.md`
- Modify: `commands/config.md`
- Create: `tests/install.test.js`

**Interfaces:**
- Produces: `install.js` sets `statusLine.command` to `node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"`; `uninstall.js` removes it (matching new + legacy forms) and preserves the config file.

- [ ] **Step 1: Create `scripts/install.js`**

```javascript
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const claudeDir = path.join(os.homedir(), '.claude');
const settings = path.join(claudeDir, 'settings.json');
const legacyScript = path.join(claudeDir, 'glm-usage-status.sh');

fs.mkdirSync(claudeDir, { recursive: true });

let cfg = {};
if (fs.existsSync(settings)) { cfg = JSON.parse(fs.readFileSync(settings, 'utf8')); }
const stamp = new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14);
const backup = path.join(claudeDir, `settings.json.backup.${stamp}.${process.pid}`);
if (fs.existsSync(settings)) { fs.copyFileSync(settings, backup); console.log(`Backed up settings to ${backup}`); }
else { fs.writeFileSync(settings, '{}\n'); }

if (fs.existsSync(legacyScript)) { fs.unlinkSync(legacyScript); console.log(`Removed legacy script copy ${legacyScript}`); }

cfg.statusLine = {
  type: 'command',
  command: 'node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"',
  refreshInterval: 60,
  padding: 1,
};
fs.writeFileSync(settings, JSON.stringify(cfg, null, 2) + '\n');
console.log('Configured GLM quota status line to use the plugin Node script. Restart Claude Code to display it.');
```

- [ ] **Step 2: Create `scripts/uninstall.js`**

```javascript
#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const claudeDir = path.join(os.homedir(), '.claude');
const settings = path.join(claudeDir, 'settings.json');
const configFile = path.join(claudeDir, 'glm-quota.json');

if (fs.existsSync(settings)) {
  const cfg = JSON.parse(fs.readFileSync(settings, 'utf8'));
  const cmd = (cfg.statusLine && cfg.statusLine.command) || '';
  // Matches the new node form, the prior bash ${CLAUDE_PLUGIN_ROOT} form,
  // and the legacy copy form (glm-usage-status.sh) — all are removed.
  if (cmd.includes('CLAUDE_PLUGIN_ROOT') || cmd.includes('glm-usage-status.sh')) {
    delete cfg.statusLine;
    fs.writeFileSync(settings, JSON.stringify(cfg, null, 2) + '\n');
  }
}
if (fs.existsSync(configFile)) {
  console.log(`Preserved user config at ${configFile} (remove manually if desired).`);
}
console.log('Removed GLM quota status line setting. Existing settings backups were preserved.');
```

- [ ] **Step 3: Rewrite `commands/setup.md`**

```markdown
---
description: Install or update the GLM Coding Plan quota status line
allowed-tools: Bash
---

Explain that setup will back up `~/.claude/settings.json`, point the
`statusLine` setting at the plugin's Node script
(`node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"`), and merge only the
`statusLine` key. If an older copy-based install exists at
`~/.claude/glm-usage-status.sh`, setup removes it. It reuses the existing
`ANTHROPIC_AUTH_TOKEN` and never prints or stores the token. Requires Node.js
(provided by Claude Code).

After the user approves, run:

\`\`\`bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/install.js"
\`\`\`

Report the command result and remind the user to restart Claude Code.
```

- [ ] **Step 4: Rewrite `commands/usage.md`**

```markdown
---
description: Query and display current GLM Coding Plan quota once
allowed-tools: Bash
---

Run the plugin status-line script once:

\`\`\`bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js" < /dev/null
\`\`\`

Return the rendered five-hour and weekly remaining quota. If weekly displays
`N/A`, explain that the domestic endpoint did not return a weekly quota entry.
```

- [ ] **Step 5: Rewrite `commands/config.md`**

```markdown
---
description: Customize GLM quota status-line thresholds, colors, and bar width
allowed-tools: Read, Write, AskUserQuestion
---

Help the user customize the GLM quota status line. The config file is
`~/.claude/glm-quota.json`. Allowed color names: green, orange, red, yellow,
blue, cyan, magenta, gray, white.

1. Read the existing config (if any) with Read:
   `~/.claude/glm-quota.json`

2. Using AskUserQuestion, guide the user through:
   - bar width: an integer 1–20 (default 10)
   - number of levels (default 3)
   - for each level, a threshold `min` (remaining percent the level starts at,
     an integer 0–100) and a color name from the allowed set.
   Defaults if no config exists: barWidth 10, levels
   `[{min:70,color:green},{min:30,color:orange},{min:0,color:red}]`.

3. Validate before writing:
   - barWidth integer in 1–20
   - at least one level
   - each `min` integer 0–100
   - `min` values strictly descending
   - last level's `min` exactly 0
   - each color in the allowed set
   If any check fails, explain the broken constraint and re-ask that value.

4. Write the result to `~/.claude/glm-quota.json` with the Write tool.

5. Tell the user to reload or restart Claude Code for the change to take effect,
   and show a preview of the chosen levels.
```

- [ ] **Step 6: Create `tests/install.test.js`**

```javascript
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
```

- [ ] **Step 7: Run the tests**

Run: `node --test tests/`
Expected: all PASS (statusline + cache + install). `node --check scripts/install.js scripts/uninstall.js` clean.

- [ ] **Step 8: Commit**

```bash
git add scripts/install.js scripts/uninstall.js commands/setup.md commands/usage.md commands/config.md tests/install.test.js
git commit -m "feat: rewrite install/uninstall in Node; point commands at node scripts"
```

---

### Task 4: Delete the bash scripts/tests and update README

**Files:**
- Delete: `scripts/statusline.sh`, `scripts/install.sh`, `scripts/uninstall.sh`
- Delete: `tests/test-statusline.sh`, `tests/test-cache.sh`, `tests/test-install.sh`
- Modify: `README.md`

- [ ] **Step 1: Delete the bash files**

```bash
git rm scripts/statusline.sh scripts/install.sh scripts/uninstall.sh
git rm tests/test-statusline.sh tests/test-cache.sh tests/test-install.sh
```

- [ ] **Step 2: Update `README.md`**

- Requirements: drop `jq`/`curl`/`Bash 3.2`; state "Claude Code (provides Node.js)" and "Git Bash on Windows (bundled with Git)".
- Install JSON example: `"command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js\""`.
- Development section test commands: `node --check scripts/*.js` and `node --test tests/`.
- Note the plugin runs on Windows, macOS, and Linux with no external dependencies (Node ships with Claude Code).

- [ ] **Step 3: Run the full Node suite**

Run: `node --test tests/`
Expected: all PASS. Also `node --check scripts/statusline.js scripts/install.js scripts/uninstall.js`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: drop bash/jq scripts and tests; document cross-platform Node runtime"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- statusline.js (fetch/cache/config/render/fallbacks) → Task 2.
- install.js / uninstall.js (no jq, migration, preserve config) → Task 3.
- commands call `node ...` → Task 3 (setup/usage/config).
- Tests migrate to `node:test`, Windows-runnable → Tasks 2 & 3.
- Fixtures reused unchanged → Task 2 run helper points at `tests/fixtures/`.
- README updated → Task 4.
- Migration for existing users → install.js removes legacy copy (Task 3).
- Windows validation gate → Task 1.

**Placeholder scan:** All code steps contain complete, final code. README update (Task 4 Step 2) is intentionally prose-level (it summarizes prior tasks); it has no code placeholders.

**Name consistency:** `configValid`, `loadConfig`, `extractFields`, `renderQuota`, `shouldRefresh`, `saveCache`, `cachePath`, `DEFAULT_LEVELS`, `DEFAULT_BAR_WIDTH` are exported in Task 2 and imported by both test files consistently. The `statusLine.command` value `node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"` is identical across install.js, setup.md, install.test.js, and the README example.
