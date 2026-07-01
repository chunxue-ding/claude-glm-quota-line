#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUSLINE="$ROOT/scripts/statusline.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/tmp"

# Fake curl: write the fixture body to whichever file -o names, ignore the rest.
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "-o" ]; then
    out="${args[$((i + 1))]}"
    break
  fi
done
printf '%s' "$GLM_QUOTA_FAKE_BODY" > "$out"
EOF
chmod +x "$TEST_ROOT/bin/curl"

export TMPDIR="$TEST_ROOT/tmp"
export ANTHROPIC_AUTH_TOKEN="fake-token"
export ANTHROPIC_BASE_URL="https://example.test/api/anthropic"
export GLM_QUOTA_FAKE_BODY="$(cat "$ROOT/tests/fixtures/green.json")"

printf '{}' | env PATH="$TEST_ROOT/bin:$PATH" "$STATUSLINE" >/dev/null

CACHE="$TMPDIR/glm-coding-plan-quota-${USER:-user}.json"
test -f "$CACHE"
perms="$(stat -f '%Lp' "$CACHE" 2>/dev/null || stat -c '%a' "$CACHE")"
if [ "$perms" != "600" ]; then
  printf 'Expected cache file perms 600, got %s\n' "$perms" >&2
  exit 1
fi

printf 'cache permission tests passed\n'
