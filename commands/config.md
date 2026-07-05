---
description: Customize GLM quota status-line thresholds, colors, and bar width
allowed-tools: Bash, Read, Write, AskUserQuestion
---

Help the user customize the GLM quota status line. The config file is
`~/.claude/glm-quota.json`. Allowed color names: green, orange, red, yellow,
blue, cyan, magenta, gray, white.

1. Read the existing config (if any) to use as starting defaults:

```bash
cat ~/.claude/glm-quota.json 2>/dev/null || true
```

2. Using AskUserQuestion, guide the user through:
   - bar width: an integer 1–20 (default 10)
   - number of levels (default 3)
   - for each level, a threshold `min` (remaining percent the level starts at,
     an integer 0–100) and a color name from the allowed set.

   Defaults if no config exists: barWidth 10, levels
   `[{min:70,color:green},{min:30,color:orange},{min:0,color:red}]`.

3. Validate before writing:
   - barWidth is an integer in 1–20
   - there is at least one level
   - each `min` is an integer in 0–100
   - `min` values are strictly descending
   - the last level's `min` is exactly 0
   - each color is in the allowed set

   If any check fails, explain the broken constraint and re-ask that value.

4. Write the result to `~/.claude/glm-quota.json` with owner-only permissions:

```bash
tmp="$(mktemp)"
cat > "$tmp" <<'JSON'
<paste the built JSON here>
JSON
mv "$tmp" ~/.claude/glm-quota.json
chmod 600 ~/.claude/glm-quota.json
```

5. Tell the user to reload or restart Claude Code for the change to take effect,
   and show a preview of the chosen levels.
