---
name: autoplex
description: >
  Production-grade autonomous plan execution engine for Claude Code. NOT a
  simple ralph-style while loop — autoplex is an execution system with five
  unique mechanisms: (1) failure-type-aware adaptive retry that rewrites prompts
  based on 5 detected failure modes (context overflow, rate limit, budget,
  API error, generic), (2) per-task 6-step methodology injection (context load,
  parallel research subagents, implementation, verification, cross-verification,
  commit) embedded in every prompt, (3) phase-level cross-review quality gates
  via independent claude -p sessions with multi-agent verification, (4)
  crash-resumable progress tracking via progress.md ledger, (5) per-task budget
  allocation with dynamic +$3/+$5 adjustment on retry. Each task runs in a
  completely fresh headless session — zero context leakage between tasks.
  Use when: (1) user has a task_plan.md with phased tasks and wants to execute
  them autonomously, (2) user says "run the plan", "execute tasks", "automate
  the phases", "run overnight", or similar, (3) user wants to batch-execute
  tasks from a planning-with-files session without babysitting, (4) user
  references autonomous execution, headless loops, or unattended agent runs,
  (5) user wants to continue executing remaining tasks from a prior run,
  (6) user asks how to run Claude Code tasks in a loop or batch mode.
  Do NOT use for: single-task execution, interactive coding, plan creation
  (use the plan skill instead), or tasks without an existing task_plan.md.
---

# Autoplex

Execute a multi-phase `task_plan.md` unattended via `claude -p` headless sessions, with per-task retry, phase-end cross-review audits, and tmux-based monitoring.

## When to Use

- A `task_plan.md` exists (created via the planning-with-files pattern)
- The plan has multiple tasks organized into phases
- The user wants autonomous, unattended execution
- Tasks are independent enough to run in separate Claude sessions

## Prerequisites

- `claude` CLI installed and authenticated
- Project is a git repository
- Plan directory contains: `task_plan.md`, `progress.md` (and optionally `findings.md`)
- The plan follows the planning-with-files convention with a Cross-Reference Ledger in `progress.md`

---

## How It Works

The executor generates a bash script that loops through tasks sequentially. Each task invocation is a fresh `claude -p` session (automatic context clearing). The flow:

```
For each task in phase order:
  1. Check progress.md — skip if already DONE
  2. Generate a structured prompt with full methodology
  3. Invoke: claude -p < prompt_file --model opus --effort max
  4. On failure: detect failure type from log, adapt prompt, retry (up to 2x)
  5. On success: log result, notify, continue

After all tasks in a phase:
  6. Run phase-level cross-review audit (separate claude -p session)
  7. Review fixes any critical/warning issues, commits fix
  8. Continue to next phase
```

---

## Step 1: Analyze the Plan

Read the user's `task_plan.md` and `progress.md` to understand:

1. **Which tasks remain** — check the Cross-Reference Ledger for status (DONE vs pending)
2. **Phase groupings** — how tasks are organized into phases
3. **Dependencies** — any HARD PREREQUISITE annotations between tasks
4. **Scope** — which phases the user wants to execute (they may want a subset)

Ask the user:

- Which phases/tasks to include in this run?
- Budget per task? (suggest based on complexity — simple $6-8, medium $10-12, complex $15-18)
- Permission mode? (`--skip-permissions` for fully unattended, default `auto` for semi-supervised)
- What is the project's verification command? (e.g., `pnpm verify`, `npm test`, `cargo test`)
- What commit message format does the project use? (e.g., `refactor(ui): T6 — description`)
- Does the project have cross-verification tools? (Codex MCP, GemSuite MCP, or skip)

## Step 2: Generate the Execution Script

Use the template in `scripts/generate-executor.sh` as a reference, but generate a **project-specific** script. Customize:

- `PROJECT_DIR` and `PLAN_DIR` paths
- Task list (format: `"PHASE:TASK_ID:DESCRIPTION"`)
- Per-task budgets via the `get_task_budget()` case function
- `{VERIFY_COMMAND}` — project's verification command(s)
- `{COMMIT_FORMAT}` — project's commit message convention
- `{CROSS_VERIFY_STEPS}` — project-specific cross-verification (Codex, GemSuite, or omit)
- `{PROJECT_SPECIFIC_CONTEXT}` — any cascade awareness, edge cases, or domain knowledge

### Critical Script Requirements (Learned from Production)

These are non-negotiable — each was discovered through real failures:

1. **bash 3.2 compatibility** — macOS ships bash 3.2 which lacks `declare -A` (associative arrays). Use a `case` function for per-task budget lookup instead.

2. **`pipefail` + `grep` interaction** — `grep -v` returns exit code 1 when no lines match. With `set -euo pipefail`, this kills the script. Always wrap: `{ grep -v PATTERN || true; }`.

3. **`CLAUDECODE` environment variable** — When launched from within a Claude Code session, child `claude` processes detect `CLAUDECODE` and refuse to start ("nested session" error). The tmux wrapper MUST `unset CLAUDECODE`.

4. **Prompt transmission** — Long prompts piped via `echo "$prompt" | claude -p` can be truncated or cause "Prompt is too long" errors. Write to a temp file and redirect: `claude -p < "$prompt_file"`.

5. **macOS has no `timeout` command** — Implement manual timeout via background process + poll loop (`sleep 5`, check `kill -0 $pid`). Do NOT depend on `timeout` or `gtimeout`.

6. **`claude -p` buffers output** — Log files remain empty until the session completes. This is normal — do not interpret empty logs as failure during monitoring.

7. **SIGTERM may not kill `claude`** — The timeout handler should try SIGTERM first, then escalate to `kill -9` (SIGKILL) after a grace period. See the template's `run_claude()` function.

8. **tmux needs a zsh wrapper** — tmux sessions don't inherit the parent shell's PATH. The wrapper must: source `~/.zprofile` + `~/.zshrc`, export PATH, unset CLAUDECODE, then exec the bash script.

9. **Wrapper must capture correct exit code** — When using `bash script.sh | tee logfile`, the exit code of `$?` is from `tee` (always 0). Use zsh's `${pipestatus[1]}` or bash's `${PIPESTATUS[0]}` to get the script's actual exit code.

### Task Prompt Template

Each task gets a structured 6-step prompt. This is the core methodology — adapt project-specific parts but preserve the structure:

```
ultrathink

You are executing a single task from a multi-phase [PLAN_NAME] plan.
This is a headless autonomous session — complete the task fully,
verify, commit, and update progress without human interaction.

## Your Task
**Phase {PHASE} — {TASK_ID}: {TASK_DESC}**

## Step 1: Context Loading (MANDATORY — do this FIRST)
Read these files IN ORDER:
1. `{PLAN_DIR}/task_plan.md` — Find the {TASK_ID} section. Read the ENTIRE
   section. Also read: "Execution Methodology", key decisions, prerequisites.
2. `{PLAN_DIR}/findings.md` — Research context (if exists)
3. `{PLAN_DIR}/progress.md` — Cross-Reference Ledger, lessons from prior tasks

## Step 2: Pre-Implementation Research
Use the Agent tool to launch parallel research subagents (model="sonnet"):
- Agent 1: Search codebase for ALL files to modify. Exact line numbers + counts.
- Agent 2: Read reference files cited in the task (if any).
- Agent 3: Check existing tests covering files being modified.
Wait for ALL agents before proceeding. Cross-reference findings.

## Step 3: Implementation
Follow the task plan's instructions. Apply these rules:

**GOAL > PLAN**: The task defines WHAT. Steps are suggestions.
Adapt if line numbers shifted or simpler paths exist.

**SYSTEMATIC**: For mechanical replacements, grep ALL instances first,
then replace methodically. grep is truth, not memory.

**LLM ANTI-PATTERNS TO AVOID**:
- Before creating anything new, search if it already exists
- Prefer reusing existing patterns over inventing new ones
- If modifying shared code, trace ALL consumers
- Check imports — if you rename/move, update all references

{PROJECT_SPECIFIC_CONTEXT}

**COMMIT DISCIPLINE**: Stage only intentionally changed files.
Use `git diff --stat` to verify before committing.

## Step 4: Verification (MANDATORY)
Run: {VERIFY_COMMAND}
If tests fail: the test is RIGHT until proven otherwise. Fix code, not tests.

## Step 5: Cross-Verification (use subagents)
{CROSS_VERIFY_STEPS}
Wait for ALL. Fix issues found. Re-verify if fixes made.

## Step 6: Commit & Progress Update
1. Commit: `{COMMIT_FORMAT}`
2. Update {PLAN_DIR}/progress.md:
   - Ledger: {TASK_ID} → DONE + session notes
   - Brief entry: files changed, key changes, deviations
```

### Phase Review Prompt Template

```
ultrathink

You are performing a Phase-level cross-review audit. This is a quality gate.

## Phase {PHASE} Cross-Review Audit

### Step 1: Context Loading
1. Read task_plan.md — Phase {PHASE} goals
2. Read progress.md — what was done, deviations
3. Read findings.md — baseline (if exists)

### Step 2: Gather Changes
Run: `git log --oneline --since="8 hours ago"`
Run: `git diff <first-commit>~1..HEAD --stat`
Read each changed file.

### Step 3: Launch Parallel Review Agents
1. Code Review Agent (subagent_type="code-reviewer")
2. {CROSS_VERIFY_STEPS — expanded for review scope}
3. Project verification command
WAIT for ALL agents. Do NOT write conclusions while running.

### Step 4: Cross-Reference Findings
List every issue by severity (critical/warning/info).

### Step 5: Fix Issues
Fix ALL critical and warning issues. Re-verify.

### Step 6: Commit & Report
Commit fixes. Update progress.md with review status.
```

### Retry Logic

When a task fails, the script inspects the log for failure patterns and adapts the retry prompt:

| Failure Type     | Log Pattern                                             | Retry Strategy                                       |
| ---------------- | ------------------------------------------------------- | ---------------------------------------------------- |
| Context overflow | `context.*window`, `token.*limit`, `Prompt is too long` | Skip findings.md, fewer subagents, budget +$3        |
| Rate limited     | `rate.*limit`, `429`, `overloaded`                      | Wait and retry normally                              |
| Budget exceeded  | `budget.*exceeded`, `max.*budget`                       | Minimize cross-verification, budget +$5              |
| API error        | `api.*error`, `500`, `503`                              | Retry normally (transient)                           |
| Generic failure  | Any other non-zero exit                                 | Check git diff for partial work, continue from there |

API errors that occur during an otherwise-successful run (exit code 0) are logged as warnings but do not trigger retry — this is expected behavior when subagent MCP calls occasionally fail.

## Step 3: Generate the tmux Wrapper

Create a **zsh** wrapper script (NOT bash — tmux's default shell may not load your PATH). The wrapper must:

1. Source `~/.zprofile` then `~/.zshrc` for PATH (order matters — profile first)
2. `cd` to the project directory
3. `export PATH` so child bash processes inherit it
4. `unset CLAUDECODE` to prevent nested-session detection
5. Print environment diagnostics: paths to `claude`, project tools (`pnpm`/`npm`/`cargo`), and `timeout`
6. Run the executor: `bash scripts/executor.sh --skip-permissions 2>&1 | tee "$LOGFILE"`
7. Capture correct exit code: `EXIT_CODE=${pipestatus[1]:-$?}` (zsh syntax for pipe element)
8. Wait for keypress before closing: `read -k 1` (zsh) — keeps tmux window open on completion

Example wrapper (adapt paths):

```zsh
#!/usr/bin/env zsh
[[ -f ~/.zprofile ]] && source ~/.zprofile 2>/dev/null
[[ -f ~/.zshrc ]] && source ~/.zshrc 2>/dev/null
cd /path/to/project || exit 1
export PATH
unset CLAUDECODE 2>/dev/null || true

LOGFILE="logs/executor/run-$(date +%Y%m%d_%H%M).log"
mkdir -p logs/executor

echo "Starting at $(date)"
echo "Claude: $(which claude 2>/dev/null || echo 'NOT FOUND')"
echo ""

bash scripts/executor.sh --skip-permissions 2>&1 | tee "$LOGFILE"
EXIT_CODE=${pipestatus[1]:-$?}
echo "Exited with code $EXIT_CODE at $(date)"
echo "Press any key to close..."
read -k 1
```

## Step 4: Dry-Run Verification

Before launching, ALWAYS run with `--dry-run` to confirm:

- Task list is correct (right tasks, right order)
- Budget allocation is reasonable
- No tasks are incorrectly marked as DONE

Show the user the dry-run output and get explicit confirmation before real execution.

## Step 5: Launch and Monitor

Start execution:

```bash
tmux new-session -d -s {SESSION_NAME} "zsh scripts/{WRAPPER_NAME}.sh"
```

Provide monitoring commands:

```bash
# Attach to live session
tmux attach -t {SESSION_NAME}

# Check from outside
tmux capture-pane -t {SESSION_NAME} -p | tail -20

# Check process
ps aux | grep "claude -p" | grep -v grep

# Check commits
git log --oneline -5
```

Monitor periodically (every 5-10 min for active tasks). Report:

- Current task and elapsed time
- Completed task count
- Any retries or warnings
- New git commits

## Step 6: Post-Execution

After all tasks complete:

1. Show full execution summary (from tmux capture)
2. Show all new git commits
3. Read updated `progress.md` to confirm all tasks marked DONE
4. Kill the tmux session: `tmux kill-session -t {SESSION_NAME}`
5. Note any warnings or review issues for the user to inspect

---

## Configuration Defaults

| Setting         | Default       | Notes                                          |
| --------------- | ------------- | ---------------------------------------------- |
| Model           | opus          | Use sonnet for simple tasks to save cost       |
| Effort          | max           | High quality for autonomous execution          |
| Permission mode | auto          | `bypassPermissions` for fully unattended       |
| Task timeout    | 2400s (40min) | Increase for very large tasks                  |
| Review timeout  | 2400s (40min) | Reviews with many subagents often exceed 30min |
| Max retries     | 2             | 3 total attempts per task (1 + 2 retries)      |
| Retry delay     | 15s           | Prevents rate limit hammering                  |
| Default budget  | $10-12        | Scale by complexity: $6-18                     |
| Review budget   | $10           | Reviews need subagents                         |

---

## Common Issues and Solutions

**Script exits immediately**: Check `set -euo pipefail` interactions. Any command in a pipeline returning non-zero kills the script. Wrap `grep` with `|| true`.

**"Prompt is too long"**: The task plan section is too large for `claude -p` input. The retry mechanism handles this by stripping findings.md and reducing verbosity.

**Claude process runs beyond timeout**: The timeout handler tries SIGTERM, then SIGKILL after 10 seconds. Budget cap (`--max-budget-usd`) provides a secondary limit.

**tmux session exits immediately**: Shell environment issue. Test the wrapper directly (`zsh scripts/wrapper.sh`) before running via tmux. Check the PATH diagnostics it prints.

**No commits after task completes**: The headless Claude may have run verification but not committed (budget exhaustion mid-commit). Check `git diff --stat` for uncommitted work and commit manually.

**Review takes much longer than tasks**: This is normal — reviews launch 3-5 parallel subagents (code-reviewer, Codex, GemSuite) that each consume significant budget. If a review exceeds timeout, it's not a blocker since all task commits are already landed.

**Log files empty during execution**: `claude -p` buffers all output until session ends. This is expected — check process status with `ps aux | grep "claude -p"` instead.
