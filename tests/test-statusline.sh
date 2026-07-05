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

# Green/orange boundary: 5h remaining == 70 (the inclusive >= green threshold).
# 70% remaining -> 7 filled of 10, and must render GREEN (locks inclusive >=).
boundary="$(run_fixture quota-70-boundary)"
assert_contains "$boundary" '5h [███████░░░] 70% left'
assert_contains "$boundary" $'\033[32m'

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

# Float barWidth must be rejected and fall back to default.
float_barwidth="$(run_with_config green config-float-barwidth)"
assert_contains "$float_barwidth" '5h [████████░░] 80% left'
assert_contains "$float_barwidth" $'\033[32m'

# Integer-valued float barWidth (10.0) passes validation; reading it with
# `| floor` yields an int so bash arithmetic never sees the raw "10.0" string.
# Renders the DEFAULT-width 10-cell bar with no error on stderr.
intfloat_out="$(run_with_config green config-intfloat-barwidth 2>/tmp/intfloat-err)"
assert_contains "$intfloat_out" '5h [████████░░] 80% left'
assert_contains "$intfloat_out" $'\033[32m'
test ! -s /tmp/intfloat-err

# Duplicate level thresholds must be rejected and fall back to default.
equal_min="$(run_with_config green config-equal-min)"
assert_contains "$equal_min" '5h [████████░░] 80% left'
assert_contains "$equal_min" $'\033[32m'

printf 'statusline tests passed\n'
