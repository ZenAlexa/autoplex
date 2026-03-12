<p align="center">
  <h1 align="center">Autoplex</h1>
  <p align="center"><strong>Production-grade autonomous plan execution engine for Claude Code.</strong></p>
  <p align="center">
    The only tool that combines failure-type-aware adaptive retry, per-task methodology injection,<br/>
    phase-level cross-review quality gates, and crash-resumable progress tracking in a single system.
  </p>
</p>

<p align="center">
  <a href="#why-not-ralph">Why Not Ralph?</a> &bull;
  <a href="#the-five-mechanisms">The Five Mechanisms</a> &bull;
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#competitive-landscape">Landscape</a> &bull;
  <a href="#ecosystem">Ecosystem</a> &bull;
  <a href="ecosystem.md">Full Guide</a>
</p>

---

## The Problem

You have a structured plan with 20+ tasks across multiple phases. Every existing tool makes you choose between:

- **Simple loops** (ralph, continuous-claude) — retry blindly, no quality gates, no failure awareness
- **Heavy platforms** (ruflo/claude-flow, BMAD-METHOD) — enterprise swarm infrastructure you don't need
- **Single-session workflows** (lebed2045/orchestration) — great quality gates, but crash = start over

**Autoplex is the middle ground that doesn't compromise.** Production-grade execution with zero infrastructure dependencies — just bash, `claude -p`, and your task plan.

## Why Not Ralph?

[Ralph](https://github.com/snarktank/ralph) (12k+ stars) pioneered the `claude -p` loop pattern. But ralph is an 87-line shell script where **all intelligence lives inside Claude itself**. The orchestrator is just a `for` loop that greps stdout for `<promise>COMPLETE</promise>`.

Here's what ralph **cannot do** (verified by reading source code):

| Capability                       | Ralph                                 | Autoplex                                                                        |
| -------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------- |
| Detect WHY a task failed         | No — errors swallowed via `\|\| true` | 5 failure types detected from log analysis                                      |
| Adapt retry strategy per failure | No — same prompt every time           | Context overflow → strip context, +$3; Budget exceeded → skip cross-verify, +$5 |
| Execute multi-phase plans        | No — flat user story list             | Phase → Task hierarchy with dependency awareness                                |
| Quality gate between phases      | No — only test/lint inside Claude     | Separate review session with parallel subagents                                 |
| Resume after crash               | Partial — prd.json `passes` flag      | Full — progress.md ledger, any-task resume                                      |
| Control per-task budget          | No                                    | Per-task allocation + dynamic adjustment on retry                               |
| Inject execution methodology     | No — Claude decides what to do        | 6-step methodology embedded in every task prompt                                |

**Ralph is a prototype. Autoplex is a production system.** The gap isn't incremental — it's architectural.

### vs. Other Tools (Source-Code-Level Analysis)

| Capability                   | [ralph](https://github.com/snarktank/ralph) | [ralphex](https://github.com/umputun/ralphex) | [continuous-claude](https://github.com/AnandChowdhary/continuous-claude) | [lebed2045](https://github.com/lebed2045/orchestration) | **autoplex**                                  |
| ---------------------------- | ------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------- | --------------------------------------------- |
| **Failure-type-aware retry** | None                                        | Rate-limit wait only                          | CI retry 1x                                                              | None                                                    | 5 types + prompt adaptation                   |
| **Multi-phase execution**    | Flat list                                   | Linear sequence                               | No phases                                                                | 8-stage workflow                                        | Phase→Task with dependencies                  |
| **Phase quality gates**      | None                                        | 3-stage review pipeline                       | Optional reviewer                                                        | Gemini + isolated Claude                                | Independent session + multi-agent             |
| **Crash recovery**           | prd.json passes                             | Checkbox resume                               | PR-level (loses WIP)                                                     | **None** (single session!)                              | progress.md ledger, instant resume            |
| **Context management**       | New process (no structured rebuild)         | Template vars (minimal)                       | SHARED_TASK_NOTES.md                                                     | Single session (overflows!)                             | Fresh session + forced 6-step context rebuild |
| **Per-task budget**          | None                                        | None                                          | --max-cost global                                                        | None                                                    | Per-task allocation + dynamic +$3/+$5         |
| **Methodology injection**    | None                                        | None                                          | None                                                                     | Workflow-defined                                        | 6-step methodology in every prompt            |
| **Language**                 | 87 lines bash                               | ~5000 lines Go                                | ~2300 lines bash                                                         | Markdown slash commands                                 | 602 lines bash template                       |
| **Stars**                    | 12.6k                                       | 726                                           | 1.25k                                                                    | —                                                       | New                                           |

**Key insight**: ralphex is the closest competitor (Go, 3-stage review, crash recovery). But it lacks failure-type-aware retry, methodology injection, and per-task budget control — the three features that prevent cascading failures in long autonomous runs.

## The Five Mechanisms

These are what make autoplex a production system, not a while loop.

### 1. Failure-Type-Aware Adaptive Retry

When a task fails, the executor **parses the log file** to detect the specific failure mode, then **rewrites the retry prompt** accordingly:

| Failure Type     | Detection Pattern    | Prompt Adaptation                                       |
| ---------------- | -------------------- | ------------------------------------------------------- |
| Context overflow | `Prompt is too long` | Strip findings.md, fewer subagents, +$3 budget          |
| Rate limited     | `429`, `overloaded`  | Wait and retry normally                                 |
| Budget exceeded  | `budget.*exceeded`   | Skip cross-verification, +$5 budget                     |
| API error        | `500`, `503`         | Retry normally (transient)                              |
| Generic          | Any non-zero exit    | Run `git diff --stat` first, continue from partial work |

This is NOT dumb retry. Each failure type triggers a structurally different prompt. Context overflow gets a leaner prompt. Budget exceeded gets more money AND reduced scope. Generic failure checks what was already done and continues from there.

### 2. Per-Task Methodology Injection

Every task prompt contains the **complete 6-step methodology** — not as a suggestion, but as explicit instructions that travel with the prompt:

```
Step 1: Context Loading → Read task_plan.md + findings.md + progress.md
Step 2: Research → Launch parallel Explore subagents (sonnet)
Step 3: Implementation → Systematic grep-then-replace with anti-pattern guards
Step 4: Verification → Run project test suite ("tests are RIGHT until proven otherwise")
Step 5: Cross-Verification → Parallel MCP audit (Codex + GemSuite)
Step 6: Commit → Stage specific files, update progress ledger
```

Each step includes specific sub-instructions: Step 3 has LLM anti-pattern warnings ("before creating anything new, search if it already exists"). Step 4 has the test discipline rule. Step 5 has "wait for ALL agents before writing conclusions."

**Why this matters**: In a fresh `claude -p` session, Claude has zero memory of your conventions. Without methodology injection, each task would approach the work differently. With it, every task follows the same rigorous process.

### 3. Phase-Level Cross-Review Quality Gates

After all tasks in a phase complete, a **separate review session** launches — different prompt, different Claude process, different context:

1. Gather all commits from the phase via `git log`
2. Launch **parallel review agents**: code-reviewer (opus) + Codex MCP + GemSuite MCP
3. Wait for ALL agents, cross-reference findings
4. Classify issues by severity (critical/warning/info)
5. **Auto-fix** all critical and warning issues
6. Re-verify and commit fixes

Reviews are quality gates, not execution blockers — task commits are already landed. A review timeout won't lose work.

No other tool in this space combines "independent review session" + "multi-agent cross-verification" + "automatic fix and re-verify" in a single quality gate.

### 4. Crash-Resumable Progress Tracking

The `progress.md` Cross-Reference Ledger is the single source of truth:

```markdown
| Task | Status | Session | Notes |
| T1 | DONE | S1 | 5 files changed, integrated auth module |
| T2 | DONE | S2 | Added pagination, 3 new tests |
| T3 | TODO | | ← Execution resumes here |
```

On startup, the executor runs `grep -qE "\| *${task_id} *\| *DONE"` for each task. Done tasks are skipped instantly. You can:

- Ctrl-C at any point, resume tomorrow
- Kill the tmux session, restart the wrapper
- Add new tasks to the plan mid-run
- Mark tasks as DONE manually to skip them

Compare: lebed2045/orchestration runs in a single Claude session — crash means restart from zero. continuous-claude preserves merged PRs but loses in-progress work.

### 5. Per-Task Budget Allocation with Dynamic Adjustment

Each task gets its own budget based on complexity:

```bash
case "$1" in
  T1) echo 8 ;;    # Simple grep-replace: $8
  T7) echo 18 ;;   # Complex multi-file migration: $18
  *)  echo 10 ;;   # Default: $10
esac
```

On retry, budgets are **increased based on failure type**:

- Context overflow: +$3 (needs more room for leaner prompt)
- Budget exceeded: +$5 (task genuinely needs more)

This prevents the cascade failure pattern where one expensive task exhausts a global budget and starves subsequent tasks.

## Quick Start

### Install

```bash
# Option 1: Copy to skills directory
cp -r autoplex ~/.claude/skills/

# Option 2: Symlink
ln -s $(pwd) ~/.claude/skills/autoplex
```

### Use

In Claude Code, just say:

> _"I have a task plan. Run it autonomously."_

Or be specific:

> _"Execute Phase 2-4 of my task plan overnight. Budget $12 per task."_

### Manual Usage

```bash
# Preview what will run
./scripts/executor.sh --dry-run

# Run fully unattended
./scripts/executor.sh --skip-permissions

# Background execution via tmux
tmux new-session -d -s autoplex "zsh scripts/wrapper.sh"
tmux attach -t autoplex
```

## How It Works

```
For each task in phase order:
  1. Check progress.md — skip if DONE
  2. Generate structured prompt (6-step methodology + project context)
  3. Write prompt to temp file, invoke: claude -p < prompt_file
  4. On failure: parse log → detect failure type → adapt prompt → retry (up to 2x)
  5. On success: task updates progress.md, commits, continues

After all tasks in a phase:
  6. Launch independent review session (separate claude -p process)
  7. Review runs parallel agents → finds issues → auto-fixes → commits
  8. Continue to next phase
```

Each task is a completely isolated `claude -p` session. No context leakage, no accumulated drift, no token budget erosion across tasks.

## Real-World Performance

| Metric                      | Value                                         |
| --------------------------- | --------------------------------------------- |
| Largest run                 | 20+ tasks, 5 phases, ~5 hours                 |
| Human intervention          | Zero                                          |
| Cost                        | ~$105 total (~$5/task average)                |
| First-attempt success rate  | ~85% (remaining handled by adaptive retry)    |
| Context overflow recovery   | 100% (retry with leaner prompt always worked) |
| Phase review detection rate | Caught issues in 3/5 phases                   |

Timing by task type (Opus model, max effort):

| Task Type                             | Duration  | Budget |
| ------------------------------------- | --------- | ------ |
| Simple grep-replace                   | 5-10 min  | $3-5   |
| Medium migration (10-30 files)        | 12-22 min | $6-12  |
| Complex migration (50+ instances)     | 15-25 min | $10-16 |
| Phase review (3-5 parallel subagents) | 16-38 min | $5-10  |

## Configuration

| Setting        | Default       | Notes                                       |
| -------------- | ------------- | ------------------------------------------- |
| Model          | opus          | Use sonnet for simple tasks to save cost    |
| Effort         | max           | High quality for autonomous execution       |
| Task timeout   | 2400s (40min) | Increase for very large tasks               |
| Review timeout | 2400s (40min) | Reviews with subagents often exceed 30min   |
| Max retries    | 2             | 3 total attempts per task (1 + 2 retries)   |
| Budget         | $6-18/task    | Scaled by complexity, auto-adjusts on retry |

## Ecosystem

Autoplex is the **execution layer** of a broader autonomous development workflow:

```
  Plan                    Execute                     Verify
  ────                    ───────                     ──────
  planning-with-files  →  autoplex                 →  code-review
  superpowers:plan        (this skill)                superpowers:verify
  sequential-thinking     6-step per-task method      codex + gemsuite MCPs
```

### Companion Skills

| Skill                   | Role                                                             | Link                                                                              |
| ----------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| **planning-with-files** | Creates task_plan.md + progress.md that autoplex consumes        | [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files) |
| **superpowers**         | Writing plans, brainstorming, TDD, parallel agents, verification | [obra/superpowers](https://github.com/obra/superpowers)                           |
| **pr-review-toolkit**   | Multi-agent PR review with specialized reviewers                 | Built-in Claude Code plugin                                                       |

### MCP Servers Used

| MCP Server              | Role in Autoplex                                  | Link                                                                                      |
| ----------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| **Context7**            | Library API docs lookup during implementation     | [upstash/context7](https://github.com/upstash/context7)                                   |
| **Exa**                 | Web search for current best practices             | [exa-labs/exa-mcp-server](https://github.com/exa-labs/exa-mcp-server)                     |
| **GemSuite**            | AI-powered code review and quality analysis       | [PV-Bhat/gemsuite-mcp](https://github.com/PV-Bhat/gemsuite-mcp)                           |
| **Sequential Thinking** | Step-by-step reasoning for architecture decisions | [arben-adm/mcp-sequential-thinking](https://github.com/arben-adm/mcp-sequential-thinking) |

> **Note**: Codex and GemSuite MCPs are optional. Without them, autoplex falls back to self-review. See [ecosystem.md](ecosystem.md) for the full adaptation guide.

### Minimum Viable Setup

You need just three things:

1. A `task_plan.md` with phased tasks (any format — autoplex is flexible)
2. A `progress.md` with a status tracking table
3. A project verification command (`pnpm verify`, `npm test`, `cargo test`, etc.)

## Platform Gotchas (macOS)

These cost hours to discover. Saved here so you don't repeat them:

- **No `timeout` command** — uses background process + poll loop with SIGTERM→SIGKILL escalation
- **bash 3.2** — no associative arrays, use `case` functions
- **`set -euo pipefail` + `grep`** — `grep -v` returns 1 when no matches; wrap with `|| true`
- **`CLAUDECODE` env var** — child `claude` processes refuse to start if set; wrapper must `unset` it
- **`claude -p` buffers output** — logs are empty until session ends; check `ps aux` instead
- **Prompt transmission** — write to temp file and redirect stdin; direct piping truncates on macOS
- **tmux PATH** — doesn't inherit parent shell; wrapper must source `~/.zshrc` and export PATH
- **Pipe exit codes** — `bash script | tee log` gives tee's exit code; use `${pipestatus[1]}`

## File Structure

```
autoplex/
├── SKILL.md                          # Claude Code skill definition
├── README.md                         # This file
├── ecosystem.md                      # Full ecosystem guide with adaptation tips
├── scripts/
│   └── generate-executor.sh          # Bash script template (602 lines)
└── references/
    └── production-learnings.md       # Real-world gotchas and timing data
```

## Requirements

- **Claude Code** (`claude` CLI) installed and authenticated
- **tmux** for background execution
- A task plan following the [planning-with-files](https://github.com/OthmanAdi/planning-with-files) convention
- macOS or Linux (bash 3.2+ compatible)

## Architectural Note: Why Shell Scripts, Not Agent SDK

The [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview) (`@anthropic-ai/claude-agent-sdk`) offers programmatic agent control with structured I/O, subagent orchestration, and hooks. Some argue this is the "correct" approach.

We chose shell scripts deliberately:

1. **Zero dependencies** — any machine with `claude` CLI can run autoplex. No Node.js, no Python, no 190MB Go binary.
2. **Full transparency** — every execution step is visible in bash. No opaque runtime decisions inside a closed-source binary.
3. **Battle-tested pattern** — the ralph ecosystem (12k+ stars combined) validates that `claude -p` loops work at scale.
4. **No vendor lock-in** — the Agent SDK uses a [proprietary license](https://docs.claude.com/en/api/agent-sdk/overview), not open source. Shell scripts are MIT.
5. **Process isolation is free** — each `claude -p` call is a fresh process with clean context. The SDK requires explicit session management to achieve the same.

The trade-off is real: SDK gives you structured streaming, hooks, and `max_budget_usd` as a first-class primitive. But for "execute a plan and go to sleep", shell scripts are simpler, more transparent, and more portable.

## Origin

Born from necessity — a 25-task, 6-phase codebase migration that needed to run autonomously overnight. After manually running 5 tasks, the remaining 20 were executed entirely by this system with zero human intervention. Every retry strategy, platform workaround, and quality gate was discovered and hardened through real production failures across multiple projects.

## License

MIT
