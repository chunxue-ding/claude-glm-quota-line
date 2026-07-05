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
