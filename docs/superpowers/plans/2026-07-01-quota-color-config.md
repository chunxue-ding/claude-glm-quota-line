# Quota Color & Threshold Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users customize the GLM quota status line (level thresholds, per-level colors, bar width, level count) via a `/config` command and config file, and switch the install model to reference the plugin script through `${CLAUDE_PLUGIN_ROOT}` so plugin updates reach installed users automatically.

**Architecture:** A config file at `~/.claude/glm-quota.json` holds `barWidth` and a `levels` array (`{min, color}`). `statusline.sh` loads it (overridable via `GLM_QUOTA_CONFIG` for tests), validates it, and falls back to the built-in default on any problem. `render_quota` picks the first level whose `min` the remaining percentage meets and looks up the color by name. `install.sh` sets `statusLine.command` to `"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"` instead of copying the script. A new `commands/config.md` drives an interactive setup.

**Tech Stack:** Bash 3.2+, `jq`, `curl`. No new dependencies.

## Global Constraints

- Bash 3.2+ (macOS default); `curl` and `jq` required.
- Works on macOS and Linux (`stat`/`date` use BSD and GNU fallbacks).
- Never write or log `ANTHROPIC_AUTH_TOKEN`.
- Config file `~/.claude/glm-quota.json`, permissions 600.
- Allowed color names: `green`, `orange`, `red`, `yellow`, `blue`, `cyan`, `magenta`, `gray`, `white`. Unknown → `gray`.
- `barWidth` is an integer clamped to 1–20.
- `levels` is non-empty; each `min` is 0–100; `min` values are strictly descending; the last level's `min` is 0.
- Invalid/absent config → built-in default (green ≥70, orange 30–69, red <30, barWidth 10). The status line never crashes.
- `statusline.sh` honors `GLM_QUOTA_CONFIG` (config path override) and `GLM_QUOTA_FIXTURE` (quota data override) for testing.
- Each task ends with `bash -n scripts/*.sh tests/*.sh`, the relevant test script, and a commit.

---

### Task 1: Verify `${CLAUDE_PLUGIN_ROOT}` resolves in statusLine.command (manual gate)

**Files:**
- Temporary modification to `~/.claude/settings.json` (backed up and restored here)

**Why:** Task 3 assumes `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin directory when `statusLine.command` runs. This is documented, but must be confirmed in a real Claude Code session first. If it does NOT resolve, stop and keep the copy model in Task 3 (still do the config feature).

- [ ] **Step 1: Back up settings and set a probe command**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.probe-backup
jq '.statusLine = {"type":"command","command":"printf %s \"${CLAUDE_PLUGIN_ROOT:-NO}\"","refreshInterval":60}' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

The probe prints the value of `${CLAUDE_PLUGIN_ROOT}` (or `NO` if unset) into the status line.

- [ ] **Step 2: Restart Claude Code and read the status line**

- [ ] **Step 3: Interpret the result**

- If it shows a path like `/Users/.../.claude/plugins/cache/.../claude-glm-quota-line...` → the variable resolves. Proceed to Task 2.
- If it shows `NO` (empty/unset) or the literal `${CLAUDE_PLUGIN_ROOT}` → it does NOT resolve. Stop; keep the copy model in Task 3.

- [ ] **Step 4: Restore settings**

```bash
cp ~/.claude/settings.json.probe-backup ~/.claude/settings.json
rm -f ~/.claude/settings.json.probe-backup
```

No code commit for this task.

---

### Task 2: Make `statusline.sh` render from a config file

**Files:**
- Modify: `scripts/statusline.sh`
- Modify: `tests/test-statusline.sh`
- Create: `tests/fixtures/quota-mixed.json`
- Create: `tests/fixtures/config-custom-width-color.json`
- Create: `tests/fixtures/config-four-levels.json`
- Create: `tests/fixtures/config-invalid.json`

**Interfaces:**
- Consumes: env `GLM_QUOTA_CONFIG` (path to config JSON; default `$HOME/.claude/glm-quota.json`), env `GLM_QUOTA_FIXTURE` (existing).
- Produces: `statusline.sh` reads `barWidth` and `levels` from the config; `render_quota` becomes config-driven. Downstream tasks rely on this rendering behavior.

- [ ] **Step 1: Create the new fixtures**

`tests/fixtures/quota-mixed.json` (quota data: 5h used 45%, week used 15%):

```json
{"code":200,"data":{"level":"pro","limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":45,"nextResetTime":1782836702068},{"type":"TOKENS_LIMIT","unit":6,"percentage":15,"nextResetTime":1783268702068}]}}
```

`tests/fixtures/config-custom-width-color.json` (barWidth 5, cyan/magenta/red):

```json
{"barWidth":5,"levels":[{"min":70,"color":"cyan"},{"min":30,"color":"magenta"},{"min":0,"color":"red"}]}
```

`tests/fixtures/config-four-levels.json` (4 levels: green/yellow/orange/red):

```json
{"barWidth":10,"levels":[{"min":80,"color":"green"},{"min":50,"color":"yellow"},{"min":20,"color":"orange"},{"min":0,"color":"red"}]}
```

`tests/fixtures/config-invalid.json` (min values NOT descending → must fall back to default):

```json
{"barWidth":10,"levels":[{"min":30,"color":"green"},{"min":70,"color":"orange"},{"min":0,"color":"red"}]}
```

- [ ] **Step 2: Update `tests/test-statusline.sh`**

Replace the `run_fixture` helper and add `run_with_config`, then append new assertions. The full updated file:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUSLINE="$ROOT/scripts/statusline.sh"
export TZ=Asia/Shanghai

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\nActual: %q\n' "$expected" "$output" >&2
    exit 1
  fi
}

# Default config (force a non-existent config path so tests are isolated from
# the developer's real ~/.claude/glm-quota.json).
run_fixture() {
  GLM_QUOTA_FIXTURE="$ROOT/tests/fixtures/$1.json" \
  GLM_QUOTA_CONFIG="$ROOT/tests/fixtures/__no_such_config__.json" \
  "$STATUSLINE" <<< '{}'
}

run_with_config() {
  GLM_QUOTA_FIXTURE="$ROOT/tests/fixtures/$1.json" \
  GLM_QUOTA_CONFIG="$ROOT/tests/fixtures/$2.json" \
  "$STATUSLINE" <<< '{}'
}

green="$(run_fixture green)"
assert_contains "$green" '5h [████████░░] 80% left'
assert_contains "$green" 'week [█████████░] 90% left'
assert_contains "$green" 'reset 07-01 00:25'
assert_contains "$green" 'reset 07-06 00:25'
assert_contains "$green" $'\033[32m'

orange="$(run_fixture orange)"
assert_contains "$orange" '5h [█████░░░░░] 50% left'
assert_contains "$orange" $'\033[38;5;214m'

red="$(run_fixture red)"
assert_contains "$red" '5h [██░░░░░░░░] 20% left'
assert_contains "$red" $'\033[31m'

no_week="$(run_fixture no-week)"
assert_contains "$no_week" '5h [██████░░░░] 65% left'
assert_contains "$no_week" 'reset 07-01 00:25'
assert_contains "$no_week" 'week [░░░░░░░░░░] N/A'

fresh="$(run_fixture fresh)"
assert_contains "$fresh" '5h [██████████] 100% left · reset after use'

null_perc="$(run_fixture null-percentage)"
assert_contains "$null_perc" '5h [░░░░░░░░░░] N/A'

# Custom barWidth (5) and colors (cyan/magenta/red).
custom="$(run_with_config green config-custom-width-color)"
assert_contains "$custom" '5h [████░] 80% left'
assert_contains "$custom" $'\033[36m'

# Four levels route different remainings to different levels/colors.
four="$(run_with_config quota-mixed config-four-levels)"
assert_contains "$four" '5h [█████░░░░░] 55% left'
assert_contains "$four" $'\033[33m'
assert_contains "$four" 'week [████████░░] 85% left'
assert_contains "$four" $'\033[32m'

# Invalid config (non-descending min) falls back to the built-in default.
invalid="$(run_with_config green config-invalid)"
assert_contains "$invalid" '5h [████████░░] 80% left'
assert_contains "$invalid" $'\033[32m'

printf 'statusline tests passed\n'
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test-statusline.sh`
Expected: FAIL — the new `custom`/`four`/`invalid` assertions fail because `statusline.sh` does not yet read config and still renders width 10 with hardcoded colors.

- [ ] **Step 4: Implement config loading and helpers in `scripts/statusline.sh`**

Insert this block immediately after the line `cat >/dev/null` (before `CACHE=...`):

```bash
# --- Configuration ---
CONFIG_FILE="${GLM_QUOTA_CONFIG:-$HOME/.claude/glm-quota.json}"
DEFAULT_LEVELS='[{"min":70,"color":"green"},{"min":30,"color":"orange"},{"min":0,"color":"red"}]'
DEFAULT_BAR_WIDTH=10

color_ansi() {
  case "$1" in
    green)   printf '\033[32m' ;;
    orange)  printf '\033[38;5;214m' ;;
    red)     printf '\033[31m' ;;
    yellow)  printf '\033[33m' ;;
    blue)    printf '\033[34m' ;;
    cyan)    printf '\033[36m' ;;
    magenta) printf '\033[35m' ;;
    gray)    printf '\033[90m' ;;
    white)   printf '\033[37m' ;;
    *)       printf '\033[90m' ;;
  esac
}

config_valid() {
  jq -e '
    (.barWidth | type == "number" and . >= 1 and . <= 20) and
    (.levels | type == "array" and length > 0) and
    all(.levels[]; (.min | type == "number" and . >= 0 and . <= 100) and (.color | type == "string")) and
    ([.levels[].min] as $m | $m == ($m | sort | reverse)) and
    (.levels[-1].min == 0)
  ' "$1" >/dev/null 2>&1
}

if [ -s "$CONFIG_FILE" ] && config_valid "$CONFIG_FILE"; then
  BAR_WIDTH="$(jq -r '.barWidth' "$CONFIG_FILE")"
  LEVELS_JSON="$(jq -c '.levels' "$CONFIG_FILE")"
else
  BAR_WIDTH="$DEFAULT_BAR_WIDTH"
  LEVELS_JSON="$DEFAULT_LEVELS"
fi
```

- [ ] **Step 5: Rewrite `render_quota` to be config-driven**

Replace the entire existing `render_quota` function with:

```bash
render_quota() {
  local label="$1"
  local used="$2"
  local reset_ms="$3"
  local reset='\033[0m'

  if [ "$used" = 'N/A' ]; then
    local na_bar='' i
    for ((i = 0; i < BAR_WIDTH; i++)); do na_bar+='░'; done
    printf '%b%s [%s] N/A%b' '\033[90m' "$label" "$na_bar" "$reset"
    return
  fi

  used="$(printf '%.0f' "$used")"
  local remaining=$((100 - used))
  [ "$remaining" -lt 0 ] && remaining=0
  [ "$remaining" -gt 100 ] && remaining=100

  local color_name
  color_name="$(printf '%s' "$LEVELS_JSON" | jq -r --argjson r "$remaining" '.[] | select(.min <= $r) | .color' | head -1)"
  [ -z "$color_name" ] && color_name='gray'
  local color
  color="$(color_ansi "$color_name")"

  local width="$BAR_WIDTH"
  local filled=$((remaining * width / 100))
  local empty=$((width - filled))
  local bar=''
  local i

  for ((i = 0; i < filled; i++)); do bar+='█'; done
  for ((i = 0; i < empty; i++)); do bar+='░'; done

  local reset_display='N/A'
  if [ -n "$reset_ms" ] && [ "$reset_ms" != 'null' ]; then
    local reset_seconds=$((reset_ms / 1000))
    reset_display="$(date -r "$reset_seconds" '+%m-%d %H:%M' 2>/dev/null || date -d "@$reset_seconds" '+%m-%d %H:%M' 2>/dev/null || printf 'N/A')"
  elif [ "$used" -eq 0 ]; then
    reset_display='after use'
  fi

  printf '%b%s [%s] %d%% left · reset %s%b' "$color" "$label" "$bar" "$remaining" "$reset_display" "$reset"
}
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `bash tests/test-statusline.sh`
Expected: `statusline tests passed`

Run: `bash -n scripts/statusline.sh && bash -n tests/test-statusline.sh`
Expected: no output (syntax OK).

- [ ] **Step 7: Commit**

```bash
git add scripts/statusline.sh tests/test-statusline.sh tests/fixtures/quota-mixed.json tests/fixtures/config-custom-width-color.json tests/fixtures/config-four-levels.json tests/fixtures/config-invalid.json
git commit -m "feat: render status line from configurable thresholds, colors, and width"
```

---

### Task 3: Switch install/uninstall to reference the plugin script

**Prerequisite:** Task 1 confirmed `${CLAUDE_PLUGIN_ROOT}` expands. If it did not, keep the existing copy model and only skip the `command` value change.

**Files:**
- Modify: `scripts/install.sh`
- Modify: `scripts/uninstall.sh`
- Modify: `commands/setup.md`
- Modify: `tests/test-install.sh`

**Interfaces:**
- Produces: `install.sh` sets `statusLine.command` to `"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"` and removes any legacy `~/.claude/glm-usage-status.sh`. `uninstall.sh` removes the `statusLine` key when it points at this plugin's script (new or legacy form) and preserves `~/.claude/glm-quota.json`.

- [ ] **Step 1: Rewrite `tests/test-install.sh`**

Full updated file:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude"
printf '%s\n' '{"theme":"dark","statusLine":{"type":"command","command":"old-status"}}' > "$TEST_HOME/.claude/settings.json"

HOME="$TEST_HOME" "$ROOT/scripts/install.sh" >/dev/null

# No script copy is created under ~/.claude/.
test ! -e "$TEST_HOME/.claude/glm-usage-status.sh"
# statusLine points at the plugin script via CLAUDE_PLUGIN_ROOT.
test "$(jq -r '.statusLine.command' "$TEST_HOME/.claude/settings.json")" = '"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"'
test "$(jq -r '.statusLine.refreshInterval' "$TEST_HOME/.claude/settings.json")" = '60'
# Other settings are preserved.
test "$(jq -r '.theme' "$TEST_HOME/.claude/settings.json")" = 'dark'

# A legacy copy-based install is migrated away.
printf '%s\n' 'legacy' > "$TEST_HOME/.claude/glm-usage-status.sh"
HOME="$TEST_HOME" "$ROOT/scripts/install.sh" >/dev/null
test ! -e "$TEST_HOME/.claude/glm-usage-status.sh"

first_backup_count="$(find "$TEST_HOME/.claude" -name 'settings.json.backup.*' | wc -l | tr -d ' ')"

HOME="$TEST_HOME" "$ROOT/scripts/uninstall.sh" >/dev/null

# statusLine key removed; theme preserved.
test "$(jq -r '.theme' "$TEST_HOME/.claude/settings.json")" = 'dark'
test "$(jq -r 'has("statusLine")' "$TEST_HOME/.claude/settings.json")" = 'false'

# Uninstall preserves a user config file if present.
printf '%s\n' '{"barWidth":7}' > "$TEST_HOME/.claude/glm-quota.json"
HOME="$TEST_HOME" "$ROOT/scripts/uninstall.sh" >/dev/null
test -f "$TEST_HOME/.claude/glm-quota.json"

printf 'install tests passed\n'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-install.sh`
Expected: FAIL — install still copies the script and sets the old command.

- [ ] **Step 3: Rewrite `scripts/install.sh`**

Full updated file:

```bash
#!/usr/bin/env bash
set -euo pipefail

for command_name in bash curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
LEGACY_SCRIPT="$CLAUDE_DIR/glm-usage-status.sh"

mkdir -p "$CLAUDE_DIR"

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS"
  BACKUP="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d-%H%M%S).$$"
  cp "$SETTINGS" "$BACKUP"
  printf 'Backed up settings to %s\n' "$BACKUP"
else
  printf '%s\n' '{}' > "$SETTINGS"
fi

# Migrate away any legacy copy-based install.
if [ -f "$LEGACY_SCRIPT" ]; then
  rm -f "$LEGACY_SCRIPT"
  printf 'Removed legacy script copy %s\n' "$LEGACY_SCRIPT"
fi

TMP="$SETTINGS.tmp.$$"
jq '.statusLine = {
  "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh\"",
  "refreshInterval": 60,
  "padding": 1
}' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

printf 'Configured GLM quota status line to use the plugin script. Restart Claude Code to display it.\n'
```

- [ ] **Step 4: Rewrite `scripts/uninstall.sh`**

Full updated file:

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf 'Missing required command: jq\n' >&2
  exit 1
fi

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
CONFIG_FILE="$CLAUDE_DIR/glm-quota.json"

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS"
  COMMAND="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
  case "$COMMAND" in
    *'${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh'* | *'~/.claude/glm-usage-status.sh'*)
      TMP="$SETTINGS.tmp.$$"
      jq 'del(.statusLine)' "$SETTINGS" > "$TMP"
      mv "$TMP" "$SETTINGS"
      ;;
  esac
fi

if [ -f "$CONFIG_FILE" ]; then
  printf 'Preserved user config at %s (remove manually if desired).\n' "$CONFIG_FILE"
fi

printf 'Removed GLM quota status line setting. Existing settings backups were preserved.\n'
```

- [ ] **Step 5: Update `commands/setup.md`**

Full updated file:

```markdown
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

\`\`\`bash
"${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
\`\`\`

Report the command result and remind the user to restart Claude Code.
```

- [ ] **Step 6: Run all install/cache tests and syntax checks**

Run: `bash tests/test-install.sh`
Expected: `install tests passed`

Run: `bash tests/test-cache.sh`
Expected: `cache permission tests passed`

Run: `bash -n scripts/install.sh scripts/uninstall.sh`
Expected: no output (syntax OK).

- [ ] **Step 7: Commit**

```bash
git add scripts/install.sh scripts/uninstall.sh commands/setup.md tests/test-install.sh
git commit -m "feat: reference plugin script via CLAUDE_PLUGIN_ROOT instead of copying"
```

---

### Task 4: Add the `/config` command

**Files:**
- Create: `commands/config.md`

**Interfaces:**
- Produces: `commands/config.md` — a Claude command that interactively builds and writes `~/.claude/glm-quota.json`. Validation is also enforced by `statusline.sh` (Task 2), so an imperfect config degrades gracefully rather than breaking the status line.

**Note on testing:** A command file is a prompt for Claude, not executable code, so it has no automated unit test. Correctness is ensured by (a) `statusline.sh`'s validation/fallback (Task 2) and (b) `bash -n`/manual review of the file. The command's write target (`~/.claude/glm-quota.json`) is already covered by the Task 2 fixtures.

- [ ] **Step 1: Create `commands/config.md`**

Full file:

```markdown
---
description: Customize GLM quota status-line thresholds, colors, and bar width
allowed-tools: Bash, Read, Write
---

Help the user customize the GLM quota status line. The config file is
`~/.claude/glm-quota.json`. Allowed color names: green, orange, red, yellow,
blue, cyan, magenta, gray, white.

1. Read the existing config (if any) to use as starting defaults:

\`\`\`bash
cat ~/.claude/glm-quota.json 2>/dev/null || true
\`\`\`

2. Using AskUserQuestion, guide the user through:
   - bar width: an integer 1–20 (default 10)
   - number of levels (default 3)
   - for each level, a threshold `min` (remaining percent the level starts at,
     an integer 0–100) and a color name from the allowed set.

   Defaults if no config exists: barWidth 10, levels
   `[{min:70,color:green},{min:30,color:orange},{min:0,color:red}]`.

3. Validate before writing:
   - barWidth is an integer in 1–20
   - there is at least one level
   - each `min` is an integer in 0–100
   - `min` values are strictly descending
   - the last level's `min` is exactly 0
   - each color is in the allowed set

   If any check fails, explain the broken constraint and re-ask that value.

4. Write the result to `~/.claude/glm-quota.json` with owner-only permissions:

\`\`\`bash
tmp="$(mktemp)"
cat > "$tmp" <<'JSON'
<paste the built JSON here>
JSON
mv "$tmp" ~/.claude/glm-quota.json
chmod 600 ~/.claude/glm-quota.json
\`\`\`

5. Tell the user to reload or restart Claude Code for the change to take effect,
   and show a preview of the chosen levels.
```

- [ ] **Step 2: Syntax/lint check**

Run: `bash -n scripts/*.sh tests/*.sh`
Expected: no output.

(There is no shell to lint in `config.md`; confirm the fenced `bash` blocks parse by eye.)

- [ ] **Step 3: Commit**

```bash
git add commands/config.md
git commit -m "feat: add /config command for interactive quota display customization"
```

---

### Task 5: Update README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: all prior tasks. This is documentation only.

- [ ] **Step 1: Update the README**

Add a "Customization" section describing `~/.claude/glm-quota.json`, the `/config` command, the color-name list, the default config, and the invalid-config fallback. Update the "Direct installation" section: the installer no longer copies a script to `~/.claude/glm-usage-status.sh`; it points `statusLine.command` at `${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh`. Update the install JSON example to show the new `command` value. Note that re-running `/setup` migrates legacy copy-based installs. Add `/claude-glm-quota-line:config` to the commands list.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document quota customization and plugin-root install"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Config file (§Configuration file) → Task 2.
- Color mapping (§Color mapping) → Task 2 `color_ansi`.
- `/config` command (§`/config` command) → Task 4.
- `statusline.sh` changes (§statusline.sh changes) → Task 2.
- Failure handling/validation (§Failure handling) → Task 2 `config_valid` + fallback.
- Install architecture (§Architecture change) → Task 3.
- Uninstall preserves config → Task 3.
- Migration for existing users → Task 3 install + Task 5 README.
- `${CLAUDE_PLUGIN_ROOT}` verification → Task 1.
- Testing (§Testing) → Tasks 2 and 3.

**Placeholder scan:** The README task (Task 5 Step 1) is intentionally prose-level because it summarizes prior tasks; it has no code placeholders. All code steps contain complete code.

**Type/identifier consistency:** `BAR_WIDTH`, `LEVELS_JSON`, `color_ansi`, `config_valid`, `GLM_QUOTA_CONFIG` are used consistently across Task 2 steps. The `command` value `"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"` is identical in install.sh, test-install.sh, and uninstall.sh's match pattern.
