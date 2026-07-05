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
