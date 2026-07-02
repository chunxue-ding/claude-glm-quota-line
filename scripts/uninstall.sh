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
