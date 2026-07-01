# Claude GLM Quota Line — Color & Threshold Configuration

## Goal

Let users customize the status-line quota display: level thresholds, the color
of each level, the progress-bar width, and the number of levels. At the same
time, change the install model from "copy the script into `~/.claude/`" to
"reference the script inside the plugin directory" so that plugin updates reach
already-installed users automatically. When no config is present, behavior is
unchanged (green ≥ 70%, orange 30–69%, red < 30%, ten-cell bar).

## Scope

Two coupled changes, done together:

1. **Configuration feature** — a `/config` command plus a config file.
2. **Install architecture fix** — point `statusLine.command` at the plugin
   directory via `${CLAUDE_PLUGIN_ROOT}` instead of copying the script.

## Architecture change: installation

### Current behavior

`install.sh` copies `scripts/statusline.sh` to `~/.claude/glm-usage-status.sh`
and sets `statusLine.command` to that copy. Consequence: after a plugin update,
already-installed users keep running the old copy and never receive new
features unless they re-run `/setup`.

### New behavior

`statusLine.command` points directly at the plugin's script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh\"",
    "refreshInterval": 60,
    "padding": 1
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` is expanded by Claude Code to the plugin's install
directory (per the Plugins reference). After the plugin updates, a reload or
restart picks up the new script automatically. **Implementation step one is a
minimal verification that `${CLAUDE_PLUGIN_ROOT}` actually expands inside
`statusLine.command`; if it does not, fall back to the copy model.**

### install.sh changes

- Stop copying the script into `~/.claude/`.
- Merge the new `statusLine.command` value (keeping refreshInterval 60, padding 1).
- Still back up `settings.json` and verify `curl`/`jq`.
- **Migration**: if an existing `~/.claude/glm-usage-status.sh` exists and
  `statusLine.command` points at it, switch the command to the new value and
  remove the old copy.

### uninstall.sh changes

- Stop removing the script copy.
- Still delete the `statusLine` key only when `statusLine.command` still points
  at this plugin's script.
- **Preserve the user config file** `~/.claude/glm-quota.json`; report its path
  so the user can delete it manually if desired.

## Configuration file

Location: `~/.claude/glm-quota.json` (user-data area, persistent, not touched
by plugin updates), permissions 600.

```json
{
  "barWidth": 10,
  "levels": [
    { "min": 70, "color": "green" },
    { "min": 30, "color": "orange" },
    { "min": 0,  "color": "red" }
  ]
}
```

- `levels` is ordered by `min` descending. Rendering picks the first level
  whose `min` the remaining percentage is greater than or equal to. The last
  level must have `min: 0` as the catch-all.
- Missing, absent, or invalid file → built-in default (equivalent to the JSON
  above).

## Color mapping

`statusline.sh` carries an internal name → ANSI table:

| name    | ANSI            |
|---------|-----------------|
| green   | `\033[32m`      |
| orange  | `\033[38;5;214m`|
| red     | `\033[31m`      |
| yellow  | `\033[33m`      |
| blue    | `\033[34m`      |
| cyan    | `\033[36m`      |
| magenta | `\033[35m`      |
| gray    | `\033[90m`      |
| white   | `\033[37m`      |

An unknown color name falls back to `gray` for that level; the status line does
not error.

## `/config` command

New `commands/config.md`. Claude executes:

1. Read `~/.claude/glm-quota.json` if it exists, as the starting defaults.
2. Guide the user conversationally: bar width, number of levels, and each
   level's threshold (`min`) and color (chosen from the name menu only).
3. Write the result back to `~/.claude/glm-quota.json` (permissions 600).
4. Tell the user to reload/restart Claude Code for the change to take effect.

Validation lives in `statusline.sh` (it must degrade gracefully anyway), so
`/config` is responsible only for interaction and persistence. This keeps
validation single-sourced and unit-testable through the status-line fixtures.

## statusline.sh changes

- Read `~/.claude/glm-quota.json`; parse `barWidth` and `levels`; fall back to
  the built-in default on any problem.
- Rewrite `render_quota` to match the level dynamically from the configured
  `levels`, look up the color by name, and render a bar of the configured
  width.
- Preserve all existing fallbacks: `no token`, `unavailable`, `N/A`,
  `after use`.

## Failure handling / validation

Any of the following causes the status line to use the built-in default rather
than crash:

- config file absent
- JSON parse failure
- `levels` missing or empty
- last level's `min` is not 0
- `min` values not in descending order
- `barWidth` out of range — clamped to 1–20

A single unknown color name is handled per-level (that level falls back to
`gray`); it does not force the whole config back to the default.

## Testing

- **statusline fixtures**: a 4-level config, a custom color/width config, an
  invalid config that falls back to default, and an absent config that uses the
  default.
- **install**: `test-install.sh` asserts the new `statusLine.command` points at
  `${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh`, that no copy is created under
  `~/.claude/`, and that a pre-existing old copy is migrated away.
- **cache**: existing `test-cache.sh` continues to pass.

## Migration for existing users

Re-running `/claude-glm-quota-line:setup` switches an old copy-based install
to the new `${CLAUDE_PLUGIN_ROOT}` model and removes the stale
`~/.claude/glm-usage-status.sh`. Existing users keep working until they do; the
old copy is not broken by the change.
