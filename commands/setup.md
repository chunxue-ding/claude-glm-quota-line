---
description: Install or update the GLM Coding Plan quota status line
allowed-tools: Bash
---

Explain that setup will back up `~/.claude/settings.json`, install a status-line
script, and merge only the `statusLine` setting. It reuses the existing
`ANTHROPIC_AUTH_TOKEN` and never prints or stores the token.

After the user approves, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
```

Report the command result and remind the user to restart Claude Code.
