#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf 'Missing required command: jq\n' >&2
  exit 1
fi

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/glm-usage-status.sh"

rm -f "$STATUSLINE"

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS"
  COMMAND="$(jq -r '.statusLine.command // empty' "$SETTINGS")"
  if [ "$COMMAND" = '~/.claude/glm-usage-status.sh' ]; then
    TMP="$SETTINGS.tmp.$$"
    jq 'del(.statusLine)' "$SETTINGS" > "$TMP"
    mv "$TMP" "$SETTINGS"
  fi
fi

printf 'Removed GLM quota status line. Existing settings backups were preserved.\n'
