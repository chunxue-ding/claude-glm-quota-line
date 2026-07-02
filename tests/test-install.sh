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
