#!/usr/bin/env bash
set -u

cat >/dev/null

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

CACHE="${TMPDIR:-/tmp}/glm-coding-plan-quota-${USER:-user}.json"
SOURCE=''

if [ -n "${GLM_QUOTA_FIXTURE:-}" ]; then
  SOURCE="$GLM_QUOTA_FIXTURE"
else
  TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
  BASE_URL="${ANTHROPIC_BASE_URL:-https://open.bigmodel.cn/api/anthropic}"
  BASE_DOMAIN="$(printf '%s' "$BASE_URL" | sed -E 's#(https?://[^/]+).*#\1#')"
  TMP="${CACHE}.tmp.$$"
  SHOULD_REFRESH=1

  if [ -s "$CACHE" ] && jq -e '.data.limits | type == "array"' "$CACHE" >/dev/null 2>&1; then
    NOW="$(date +%s)"
    CACHE_MTIME="$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || printf '0')"
    CACHE_AGE=$((NOW - CACHE_MTIME))
    if [ "$CACHE_AGE" -ge 0 ] && [ "$CACHE_AGE" -lt 55 ]; then
      SHOULD_REFRESH=0
    fi
  fi

  if [ "$SHOULD_REFRESH" -eq 1 ] && [ -n "$TOKEN" ] && curl --max-time 5 -fsS \
    "${BASE_DOMAIN}/api/monitor/usage/quota/limit" \
    -H "Authorization: ${TOKEN}" \
    -H 'Accept-Language: zh-CN' \
    -H 'Content-Type: application/json' \
    -o "$TMP" 2>/dev/null; then
    if jq -e '.data.limits | type == "array"' "$TMP" >/dev/null 2>&1; then
      mv "$TMP" "$CACHE"
      chmod 600 "$CACHE"
    else
      rm -f "$TMP"
    fi
  elif [ "$SHOULD_REFRESH" -eq 1 ]; then
    rm -f "$TMP"
  fi

  if [ -s "$CACHE" ]; then
    SOURCE="$CACHE"
  elif [ -z "$TOKEN" ]; then
    printf '\033[90mGLM quota: no token\033[0m'
    exit 0
  else
    printf '\033[90mGLM quota: unavailable\033[0m'
    exit 0
  fi
fi

FIVE_H="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 3) | .percentage // empty' "$SOURCE" | head -1)"
WEEK="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 6) | .percentage // empty' "$SOURCE" | head -1)"
FIVE_RESET="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 3) | .nextResetTime // empty' "$SOURCE" | head -1)"
WEEK_RESET="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 6) | .nextResetTime // empty' "$SOURCE" | head -1)"

[ -z "$FIVE_H" ] && FIVE_H='N/A'
[ -z "$WEEK" ] && WEEK='N/A'

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

printf '\033[1mGLM\033[0m '
render_quota '5h' "$FIVE_H" "$FIVE_RESET"
printf '  '
render_quota 'week' "$WEEK" "$WEEK_RESET"
