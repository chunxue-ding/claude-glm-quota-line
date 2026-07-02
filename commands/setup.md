---
description: Install or update the GLM Coding Plan quota status line
allowed-tools: Bash
---

Explain that setup will back up `~/.claude/settings.json`, point the
`statusLine` setting at the plugin's own script
(`${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh`), and merge only the
`statusLine` key. If an older copy-based install exists at
`~/.claude/glm-usage-status.sh`, setup removes it. It reuses the existing
`ANTHROPIC_AUTH_TOKEN` and never prints or stores the token.

After the user approves, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
```

Report the command result and remind the user to restart Claude Code.
