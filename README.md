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
- Configurable bar width, thresholds, and colors via `~/.claude/glm-quota.json`.
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
2. removes any legacy copy of the status-line script from earlier installs
   (see [Migration](#migration));
3. merges the following status-line setting without replacing other settings,
   pointing Claude Code at the plugin's own script via the
   `${CLAUDE_PLUGIN_ROOT}` variable Claude Code sets at runtime:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh",
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

Or run the script directly from the plugin checkout:

```bash
printf '{}' | /path/to/claude-glm-quota-line/scripts/statusline.sh
```

## Customization

The status line's bar width, thresholds, and colors are configurable through
`~/.claude/glm-quota.json` (override the path with the `GLM_QUOTA_CONFIG`
environment variable). The file has two fields:

- `barWidth` — number of cells in each progress bar, an integer from 1 to 20.
- `levels` — an array of `{ "min": <percent>, "color": "<name>" }` entries that
  map the **remaining** quota percent to a color. Entries are matched in order,
  so `min` values must be strictly descending, and the final entry's `min` must
  be `0` to cover the bottom of the range.

Allowed `color` names: `green`, `orange`, `red`, `yellow`, `blue`, `cyan`,
`magenta`, `gray`, `white`.

For example, to widen the bars to 12 cells and switch to a blue/green/red
scheme:

```json
{
  "barWidth": 12,
  "levels": [
    { "min": 50, "color": "blue" },
    { "min": 20, "color": "green" },
    { "min": 0, "color": "red" }
  ]
}
```

The built-in default (used when the file is absent or invalid) is:

```json
{
  "barWidth": 10,
  "levels": [
    { "min": 70, "color": "green" },
    { "min": 30, "color": "orange" },
    { "min": 0, "color": "red" }
  ]
}
```

If the config file is missing, empty, or fails validation, the status line
silently falls back to the default above rather than failing.

The easiest way to edit the config is the interactive command, which validates
each value before writing:

```text
/claude-glm-quota-line:config
```

Reload or restart Claude Code after editing the config for the change to take
effect.

## Migration

Earlier versions of this plugin copied `statusline.sh` to
`~/.claude/glm-usage-status.sh` and pointed `statusLine.command` at that copy.
The installer now points `statusLine.command` at
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh` instead, so the script is always
the version shipped with the installed plugin.

Re-running `/claude-glm-quota-line:setup` (or the direct
`scripts/install.sh`) migrates an existing copy-based install automatically: it
removes the legacy `~/.claude/glm-usage-status.sh` and updates
`statusLine.command` to the plugin-root path. Your quota config file
(`~/.claude/glm-quota.json`) is left untouched.

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

Uninstallation removes the `statusLine` setting only when it still points at
this plugin's script (either the current `${CLAUDE_PLUGIN_ROOT}` path or the
legacy `~/.claude/glm-usage-status.sh` copy). Your quota config file
(`~/.claude/glm-quota.json`), other Claude Code settings, and existing backups
are preserved.

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
