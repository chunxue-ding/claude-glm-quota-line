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
