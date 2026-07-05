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
