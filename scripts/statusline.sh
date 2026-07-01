#!/usr/bin/env bash
set -u

cat >/dev/null

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

FIVE_H="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 3) | .percentage' "$SOURCE" | head -1)"
WEEK="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 6) | .percentage' "$SOURCE" | head -1)"
FIVE_RESET="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 3) | .nextResetTime // empty' "$SOURCE" | head -1)"
WEEK_RESET="$(jq -r '.data.limits[]? | select(.type == "TOKENS_LIMIT" and .unit == 6) | .nextResetTime // empty' "$SOURCE" | head -1)"

[ -z "$FIVE_H" ] && FIVE_H='N/A'
[ -z "$WEEK" ] && WEEK='N/A'

render_quota() {
  local label="$1"
  local used="$2"
  local reset_ms="$3"
  local width=10
  local reset='\033[0m'

  if [ "$used" = 'N/A' ]; then
    printf '%b%s [░░░░░░░░░░] N/A%b' '\033[90m' "$label" "$reset"
    return
  fi

  used="$(printf '%.0f' "$used")"
  local remaining=$((100 - used))
  [ "$remaining" -lt 0 ] && remaining=0
  [ "$remaining" -gt 100 ] && remaining=100

  local filled=$((remaining * width / 100))
  local empty=$((width - filled))
  local bar=''
  local color
  local i

  if [ "$remaining" -ge 70 ]; then
    color='\033[32m'
  elif [ "$remaining" -ge 30 ]; then
    color='\033[38;5;214m'
  else
    color='\033[31m'
  fi

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
