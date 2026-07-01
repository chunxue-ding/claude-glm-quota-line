# Claude GLM Quota Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shareable Claude Code plugin repository that installs a colored, auto-refreshing GLM Coding Plan quota status line.

**Architecture:** A portable Bash status-line script reads existing Claude Code environment variables, queries the GLM quota endpoint, caches successful responses, and renders remaining quota. Idempotent installer and uninstaller scripts merge or remove only the owned `statusLine` setting, while plugin commands provide guided setup and one-shot usage inspection.

**Tech Stack:** Bash 3.2+, curl, jq, Claude Code plugin manifest and commands.

---

### Task 1: Implement quota rendering with fixture tests

**Files:**
- Create: `scripts/statusline.sh`
- Create: `tests/fixtures/green.json`
- Create: `tests/fixtures/orange.json`
- Create: `tests/fixtures/red.json`
- Create: `tests/fixtures/no-week.json`
- Create: `tests/test-statusline.sh`

- [ ] Add a fixture override variable `GLM_QUOTA_FIXTURE` so tests bypass the network while production reads `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL`.
- [ ] Parse `TOKENS_LIMIT/unit=3` as five-hour usage and `unit=6` as weekly usage, convert each to remaining percentage, and render a ten-cell colored bar.
- [ ] Cache only valid successful responses and fall back to the last valid cache after network failure.
- [ ] Run `bash tests/test-statusline.sh`; expect all green/orange/red/N/A assertions to pass.

### Task 2: Implement safe installation and uninstallation

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `tests/test-install.sh`

- [ ] Make installation verify `bash`, `curl`, and `jq`, copy `statusline.sh` into `~/.claude`, timestamp-backup existing settings, and merge only `statusLine` with `jq`.
- [ ] Make uninstallation remove the installed script and delete `statusLine` only when its command points to `~/.claude/glm-usage-status.sh`.
- [ ] Run installer twice against a temporary `HOME` and verify idempotency and preservation of unrelated JSON fields.
- [ ] Run uninstaller against the temporary `HOME` and verify unrelated settings remain.

### Task 3: Package the Claude Code plugin

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `commands/setup.md`
- Create: `commands/usage.md`
- Create: `.gitignore`
- Create: `LICENSE`

- [ ] Add a valid plugin manifest named `claude-glm-quota-line` with its description and repository metadata.
- [ ] Add setup and usage commands that invoke `${CLAUDE_PLUGIN_ROOT}/scripts/install.sh` and the status-line script with explicit user approval.
- [ ] Validate JSON with `jq empty .claude-plugin/plugin.json` and check all referenced paths exist.

### Task 4: Document and verify the repository

**Files:**
- Create: `README.md`

- [ ] Document prerequisites, marketplace/plugin installation, direct one-command installation, output colors, authentication reuse, removal, and domestic weekly `N/A` behavior.
- [ ] Run `bash -n scripts/*.sh tests/*.sh`.
- [ ] Run `bash tests/test-statusline.sh && bash tests/test-install.sh`.
- [ ] Run `git diff --check` and review the complete repository tree.
