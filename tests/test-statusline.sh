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

run_fixture() {
  GLM_QUOTA_FIXTURE="$ROOT/tests/fixtures/$1.json" "$STATUSLINE" <<< '{}'
}

green="$(run_fixture green)"
assert_contains "$green" '5h [████████░░] 80% left'
assert_contains "$green" 'week [█████████░] 90% left'
assert_contains "$green" 'reset 07-01 00:25'
assert_contains "$green" 'reset 07-06 00:25'
assert_contains "$green" $'\033[32m'

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

printf 'statusline tests passed\n'
