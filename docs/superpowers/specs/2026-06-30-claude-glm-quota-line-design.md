# Claude GLM Quota Line Design

## Goal

Create a shareable Claude Code plugin repository that installs a colored status
line for GLM Coding Plan quota usage with one command.

## User experience

Users clone or run the repository installer once. The installer validates the
local environment, installs the status-line script, backs up and merges Claude
Code user settings, and prints the next action. Claude Code then refreshes the
quota display every 60 seconds.

The status line shows remaining quota with a ten-cell progress bar:

- 70–100% remaining: green.
- 30–69% remaining: orange/yellow.
- 0–29% remaining: red.
- Missing windows: gray `N/A`.

## Repository structure

```text
claude-glm-quota-line/
├── .claude-plugin/plugin.json
├── commands/
│   ├── setup.md
│   └── usage.md
├── scripts/
│   ├── install.sh
│   ├── statusline.sh
│   └── uninstall.sh
├── README.md
├── LICENSE
└── .gitignore
```

## Authentication and data flow

The plugin never asks for, stores, or logs an API key. The status-line process
reads the user's existing `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` values.
It derives the platform origin from the base URL and calls
`/api/monitor/usage/quota/limit`.

Quota entries are interpreted as follows:

- `TOKENS_LIMIT` with `unit=3`: five-hour window.
- `TOKENS_LIMIT` with `unit=6`: weekly window.

The API percentage is usage consumed; the display converts it to remaining
percentage. If the domestic endpoint omits the weekly entry, the plugin shows
`week: N/A` rather than estimating a value.

## Installation

`scripts/install.sh` supports macOS and Linux. It:

1. Verifies `bash`, `curl`, and `jq`.
2. Creates `~/.claude` if needed.
3. Backs up an existing `~/.claude/settings.json` with a timestamp.
4. Copies the status-line script to `~/.claude/glm-usage-status.sh`.
5. Uses `jq` to merge only the `statusLine` key, preserving all other settings.
6. Configures a 60-second refresh interval.

The installer is idempotent. Re-running it updates the script and creates a new
backup before changing settings.

## Uninstallation

`scripts/uninstall.sh` removes only the installed status-line script and removes
the `statusLine` setting only when it still points to that script. It preserves
unrelated Claude Code settings and reports available backups instead of
silently restoring an arbitrary old file.

## Plugin commands

- `/claude-glm-quota-line:setup` explains and invokes the installer with user
  approval.
- `/claude-glm-quota-line:usage` performs one quota query and explains the
  displayed windows.

## Failure handling

- Network calls time out after five seconds.
- The last successful response is cached in the system temporary directory.
- A failed refresh uses cached data when available.
- Missing authentication produces a short `no token` status without exposing
  configuration contents.
- Invalid JSON or a missing cache produces `unavailable` without breaking the
  Claude Code prompt.

## Validation

- Validate shell syntax with `bash -n`.
- Test rendering with fixture responses for green, orange, red, and missing
  weekly quota cases.
- Test installation against a temporary HOME to prove settings are merged and
  uninstall preserves unrelated configuration.
- Validate plugin metadata and command paths.
