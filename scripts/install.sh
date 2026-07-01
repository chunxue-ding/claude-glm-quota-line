#!/usr/bin/env bash
set -euo pipefail

for command_name in bash curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/glm-usage-status.sh"

mkdir -p "$CLAUDE_DIR"

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS"
  BACKUP="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d-%H%M%S).$$"
  cp "$SETTINGS" "$BACKUP"
  printf 'Backed up settings to %s\n' "$BACKUP"
else
  printf '%s\n' '{}' > "$SETTINGS"
fi

cp "$ROOT/scripts/statusline.sh" "$STATUSLINE"
chmod +x "$STATUSLINE"

TMP="$SETTINGS.tmp.$$"
jq '.statusLine = {
  "type": "command",
  "command": "~/.claude/glm-usage-status.sh",
  "refreshInterval": 60,
  "padding": 1
}' "$SETTINGS" > "$TMP"
mv "$TMP" "$SETTINGS"

printf 'Installed GLM quota status line. Restart Claude Code to display it.\n'
