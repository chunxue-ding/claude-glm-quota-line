---
description: Query and display current GLM Coding Plan quota once
allowed-tools: Bash
---

Run the plugin status-line script once with an empty Claude Code status payload:

```bash
printf '{}' | "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"
printf '\n'
```

Return the rendered five-hour and weekly remaining quota. If weekly displays
`N/A`, explain that the domestic endpoint did not return a weekly quota entry.
