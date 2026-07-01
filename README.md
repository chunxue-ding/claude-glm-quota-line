# claude-glm-quota-line

A colorful Claude Code status line for monitoring GLM Coding Plan quota in real
time.

```text
GLM 5h [████████░░] 80% left · reset 07-01 00:25  week [██████░░░░] 60% left · reset 07-06 00:25
```

## Features

- Displays five-hour and weekly remaining quota.
- Displays each quota window's local reset date and time when the API provides it.
- Ten-cell progress bars with ANSI colors:
  - green: 70% or more remaining;
  - orange: 30–69% remaining;
  - red: less than 30% remaining.
- Refreshes every 60 seconds in Claude Code.
- Reuses existing `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL`.
- Never writes or logs the API token.
- Uses the last valid cached response when a refresh fails.
- Caches quota data with owner-only (600) permissions.
- Safely merges Claude Code settings and creates timestamped backups.
- Supports macOS and Linux.

## Requirements

- Claude Code with GLM Coding Plan already configured.
- Bash 3.2 or newer.
- `curl` and `jq`.

## Install as a Claude Code plugin

In Claude Code, run:

```text
/plugin marketplace add chunxue-ding/claude-glm-quota-line
/plugin install claude-glm-quota-line@claude-glm-quota-line
/claude-glm-quota-line:setup
```

Restart Claude Code after setup.

## Direct installation

```bash
tmp="$(mktemp -d)" \
  && git clone https://github.com/chunxue-ding/claude-glm-quota-line.git "$tmp/claude-glm-quota-line" \
  && "$tmp/claude-glm-quota-line/scripts/install.sh"
```

The installer:

1. backs up `~/.claude/settings.json`;
2. installs `~/.claude/glm-usage-status.sh`;
3. merges the following status-line setting without replacing other settings:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/glm-usage-status.sh",
    "refreshInterval": 60,
    "padding": 1
  }
}
```

## Query once

After plugin installation:

```text
/claude-glm-quota-line:usage
```

Or run the installed script directly:

```bash
printf '{}' | ~/.claude/glm-usage-status.sh
```

## Domestic weekly quota behavior

The domestic endpoint may return only the five-hour quota entry. When no
`TOKENS_LIMIT` entry with `unit=6` is present, the status line shows
`week: N/A`; it does not estimate or invent a weekly percentage.

For a new rolling window with no usage, the API can return a null reset time.
The status line shows `reset after use` until the first request starts the
window, then displays the concrete local reset time.

## Uninstall

```bash
/path/to/claude-glm-quota-line/scripts/uninstall.sh
```

Uninstallation removes only this status-line script and removes the
`statusLine` setting only when it still points to the installed script. Other
Claude Code settings and backups are preserved.

## Development

```bash
bash -n scripts/*.sh tests/*.sh
bash tests/test-statusline.sh
bash tests/test-install.sh
bash tests/test-cache.sh
jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

## License

MIT
