# Production Learnings

Lessons from running this system on a real project (XAgent Design System Unification: 16 tasks, 5 phases, ~5 hours total execution).

Read this file when debugging failures or when a user reports an issue that isn't covered by SKILL.md's "Common Issues" section.

## Table of Contents

1. [Environment Issues](#environment-issues)
2. [Timing and Budget](#timing-and-budget)
3. [Failure Patterns Observed](#failure-patterns-observed)
4. [Monitoring Tips](#monitoring-tips)
5. [Script Pitfalls](#script-pitfalls)

---

## Environment Issues

### CLAUDECODE Nested Session Detection

When the automation script is launched from within a Claude Code session (common when the user says "run it"), `claude -p` detects the `CLAUDECODE` env var and exits immediately with "Cannot run nested Claude Code sessions." The wrapper script MUST `unset CLAUDECODE`.

### PATH in tmux

tmux sessions start with a minimal PATH. Commands like `claude`, `pnpm`, `node` are often installed via package managers (homebrew, volta, nvm) that modify PATH in shell profiles. The wrapper must source `~/.zprofile` and `~/.zshrc` AND export PATH so child bash processes inherit it.

### bash 3.2 on macOS

Apple ships bash 3.2 (2007 vintage) which lacks:

- `declare -A` (associative arrays) — use `case` functions instead
- `timeout` command — use background process + poll loop
- `${PIPESTATUS[@]}` works but `${pipestatus[@]}` (lowercase) is zsh-only

---

## Timing and Budget

### Real-world task durations (Opus model, max effort)

| Task Type                                            | Duration Range | Budget Used |
| ---------------------------------------------------- | -------------- | ----------- |
| Simple mechanical replacement (grep+replace)         | 5-10 min       | $3-5        |
| Medium migration (10-30 files)                       | 12-22 min      | $6-12       |
| Complex migration (50+ instances, cascade-sensitive) | 15-25 min      | $10-16      |
| Phase review (3-5 parallel subagents)                | 16-38 min      | $5-10       |

### Budget observations

- `--max-budget-usd` is a soft cap — Claude may slightly exceed it before stopping
- Cross-verification (Step 5) consumes ~30-40% of task budget due to Codex + GemSuite subagents
- On retry with budget increase (+$3 or +$5), the increased budget is applied on top of the original, not the previously-increased value. This is by design.

### Review timeout

Phase reviews consistently take longer than individual tasks because they launch 3-5 parallel subagents. The original 1800s (30min) timeout was too aggressive — reviews were killed before completing. Increased to 2400s (40min) to match task timeout.

---

## Failure Patterns Observed

### "Prompt is too long" (most common first-attempt failure)

Occurred on the largest task (T14: 9 settings pages). The combined prompt (retry preamble + full 6-step methodology + plan context) exceeded `claude -p`'s input limit. The retry mechanism successfully handled this by:

1. Detecting "Prompt is too long" in the log
2. Categorizing as `context_overflow`
3. Retry prompt: skip findings.md, fewer subagents, more concise reasoning
4. Second attempt succeeded in 5m21s

### API errors during successful runs

Several tasks completed successfully (exit code 0) but logs contained transient API errors from MCP tool calls (Codex, GemSuite). These are non-blocking — the headless Claude handled them gracefully by continuing without the failed verification step. The script correctly logs these as warnings, not failures.

### Review that exceeded all timeouts

One Phase 5 review ran for 50+ minutes, exceeding the 30min timeout. Root cause: the review launched many subagents that each consumed significant budget, and the original SIGTERM didn't kill the process (Claude caught/ignored it). Required `kill -9`. The updated template uses SIGTERM → 10s grace → SIGKILL escalation.

---

## Monitoring Tips

### Log files are empty during execution

This is the most confusing aspect for first-time users. `claude -p` buffers ALL output until the session completes. During execution, the log file exists but has 0 bytes. Check process status instead:

```bash
ps aux | grep "claude -p" | grep -v grep | awk '{printf "PID=%s CPU=%.1f%%\n", $2, $3}'
```

### How to tell if a task is making progress

1. Check CPU usage — active Claude sessions show 30-100% CPU
2. Check git working tree — `git diff --name-only` shows files being modified
3. Check new commits — `git log --oneline -5` after expected completion time

### tmux capture-pane shows stale output

`tmux capture-pane -t SESSION -p` only shows what's currently visible in the terminal window. If the script has scrolled past, you'll see old output. Use `tmux attach` for real-time view, or check the tee'd log file after task completion.

---

## Script Pitfalls

### `set -euo pipefail` gotchas

The most dangerous interaction is with `grep` in pipelines. `grep` returns exit code 1 when no lines match, which `pipefail` treats as a pipeline failure, killing the script. Always use:

```bash
some_command | { grep -v PATTERN || true; } | wc -l
```

### Retry count display confusion

`MAX_RETRIES=2` means 3 total attempts (1 original + 2 retries). The display string must use `$((MAX_RETRIES + 1))` as the denominator, not `$MAX_RETRIES`. The template uses `max_attempts=$((MAX_RETRIES + 1))` and references that variable consistently.

### Variable scope in loops

bash doesn't have block-scoped variables. Variables declared with `local` inside functions are function-scoped. In the main loop, variables like `phase`, `task_id`, `task_desc` from `IFS=':' read -r` persist across iterations. This is intentional for tracking `current_phase`.

### Exit code from pipe

`bash script.sh | tee logfile` — `$?` returns tee's exit code (always 0). The wrapper must use:

- zsh: `${pipestatus[1]}`
- bash: `${PIPESTATUS[0]}`
