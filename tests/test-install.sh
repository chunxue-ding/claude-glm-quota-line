#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.claude"
printf '%s\n' '{"theme":"dark","statusLine":{"type":"command","command":"old-status"}}' > "$TEST_HOME/.claude/settings.json"

HOME="$TEST_HOME" "$ROOT/scripts/install.sh" >/dev/null

test -x "$TEST_HOME/.claude/glm-usage-status.sh"
test "$(jq -r '.theme' "$TEST_HOME/.claude/settings.json")" = 'dark'
test "$(jq -r '.statusLine.command' "$TEST_HOME/.claude/settings.json")" = '~/.claude/glm-usage-status.sh'
test "$(jq -r '.statusLine.refreshInterval' "$TEST_HOME/.claude/settings.json")" = '60'

first_backup_count="$(find "$TEST_HOME/.claude" -name 'settings.json.backup.*' | wc -l | tr -d ' ')"
HOME="$TEST_HOME" "$ROOT/scripts/install.sh" >/dev/null
second_backup_count="$(find "$TEST_HOME/.claude" -name 'settings.json.backup.*' | wc -l | tr -d ' ')"

if [ "$second_backup_count" -le "$first_backup_count" ]; then
  printf 'Expected reinstall to create another backup\n' >&2
  exit 1
fi

HOME="$TEST_HOME" "$ROOT/scripts/uninstall.sh" >/dev/null

test ! -e "$TEST_HOME/.claude/glm-usage-status.sh"
test "$(jq -r '.theme' "$TEST_HOME/.claude/settings.json")" = 'dark'
test "$(jq -r 'has("statusLine")' "$TEST_HOME/.claude/settings.json")" = 'false'

printf 'install tests passed\n'
