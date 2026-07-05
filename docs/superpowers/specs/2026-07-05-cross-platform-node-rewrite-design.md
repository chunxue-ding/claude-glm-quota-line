# Claude GLM Quota Line — Cross-Platform Node Rewrite

## Goal

Rewrite the plugin's scripts in Node.js so the status line and installer run
with zero external dependencies on Windows, macOS, and Linux. Today the bash
scripts require `jq` (and bash), which breaks installation on Windows: Claude
Code runs `statusLine.command` via Git Bash (so bash is present), but Git Bash
does not bundle `jq`, so both the installer (jq to merge `settings.json`) and
the runtime status-line script (jq to parse quota JSON) fail. Since Claude
Code itself is a Node application, every user has Node available — Node is the
correct cross-platform runtime.

## Scope

Full replacement. The bash scripts are deleted; Node versions take over. No
bash fallback is kept — Node is guaranteed present in any Claude Code
installation, and maintaining two runtimes doubles the work for no real
benefit.

## Files

- Delete: `scripts/statusline.sh`, `scripts/install.sh`, `scripts/uninstall.sh`
- Create: `scripts/statusline.js`, `scripts/install.js`, `scripts/uninstall.js`
- Modify: `commands/setup.md`, `commands/usage.md` (call
  `node "${CLAUDE_PLUGIN_ROOT}/scripts/xxx.js"`); `commands/config.md`
  (unchanged behavior — still writes the same config file).
- Delete bash tests: `tests/test-statusline.sh`, `tests/test-cache.sh`,
  `tests/test-install.sh`.
- Create Node tests: `tests/statusline.test.js`, `tests/install.test.js`,
  `tests/cache.test.js` (using `node:test`).
- Reuse: `tests/fixtures/*.json` (quota + config fixtures, format unchanged).
- Modify: `README.md` (drop jq/bash requirements; state Node; note Windows
  support).

## statusline.js

Reads env: `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `GLM_QUOTA_CONFIG`
(default `<home>/.claude/glm-quota.json`), `GLM_QUOTA_FIXTURE`.

- **Fetch quota** via Node's built-in `https` module, 5s timeout, against
  `/api/monitor/usage/quota/limit` derived from `ANTHROPIC_BASE_URL`.
- **Cache** to `os.tmpdir()/glm-coding-plan-quota-<user>.json`, valid 55s,
  `fs.chmod 0o600` on POSIX (safe no-op on Windows). On fetch failure, use the
  cached response.
- **Load + validate config** (`barWidth` integer 1–20; `levels` non-empty, each
  min an integer 0–100, strictly descending, last min == 0; colors from the
  allowed set). Invalid/absent config → built-in default. This mirrors the
  existing `config_valid` logic exactly, including the integer and
  strict-descent guards added during the prior feature.
- **Render**: pick the first level whose `min` the remaining percentage meets,
  look up the color by name (unknown → gray), render a bar of `barWidth` cells,
  show the local reset time via `Date`. Emit ANSI (supported by modern Windows
  terminals).
- **Fallbacks preserved**: `no token`, `unavailable`, `N/A`, `after use`.
- **Never crash**: all parsing wrapped; any error → a safe fallback string and
  exit 0 (the status line must never break the Claude Code prompt).

## install.js / uninstall.js

Use `fs` / `path` / `os` (no jq).

- **install.js**: verify Node is present; back up `settings.json`; set
  `statusLine.command` to `node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"`
  with refreshInterval 60, padding 1; migrate away any legacy
  `~/.claude/glm-usage-status.sh` and old command form.
- **uninstall.js**: remove the `statusLine` key only when command points at
  this plugin (new node form, prior `${CLAUDE_PLUGIN_ROOT}` bash form, or
  legacy `~/.claude/glm-usage-status.sh`); preserve `~/.claude/glm-quota.json`.
- Paths via `os.homedir()` for a cross-platform home directory.

## /config command

`commands/config.md` keeps its conversational flow and the same config-file
contract. Only the runtime validator moves (from bash to `statusline.js`).

## Testing

Migrate to `node:test` (Node's built-in test runner) so tests run on Windows
too, not just Unix.

- `tests/statusline.test.js`: render cases (green/orange/red/N/A/after-use),
  config-driven rendering (custom width/color, 4 levels), and every validation
  rejection (float barWidth 5.5, int-valued-float barWidth 10.0, duplicate min,
  non-descending, unknown color → gray, boundary min==70 → green).
- `tests/install.test.js`: new command value, no legacy copy created, legacy
  migration, uninstall preserves config — in a temp HOME.
- `tests/cache.test.js`: cache file written with 0o600 on POSIX.
- Fixtures under `tests/fixtures/` are reused unchanged.

## Migration for existing users

Re-running `/claude-glm-quota-line:setup` invokes `install.js`, which removes
any legacy `~/.claude/glm-usage-status.sh`, switches the command to the node
form, and leaves the user's `~/.claude/glm-quota.json` untouched. Users keep
working until they re-run setup; the old bash copy is not broken by the change.

## Validation gate (before full rollout)

Step one of implementation is a manual Windows check: run
`node "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.js"` (with a fixture) under
Git Bash and confirm it renders without error. This confirms Node is on the
status-line PATH on Windows — the foundation of the whole approach. If it
fails, stop and reconsider (for example a bash fallback or a bundled runtime).

## Out of scope

- No new features beyond parity with the current bash version.
- No bundling of a Node runtime (assume Claude Code's Node is on PATH).
- No change to the config file format or the `/config` UX.
