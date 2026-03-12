<p align="center">
  <h1 align="center">Autoplex</h1>
  <p align="center"><strong>The autonomous plan execution engine for Claude Code.</strong></p>
  <p align="center">
    Turn any multi-phase task plan into a fully unattended execution pipeline.<br/>
    Each task gets a fresh headless session with research subagents, implementation, verification, cross-verification, and commit — all while you sleep.
  </p>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#ecosystem">Ecosystem</a> •
  <a href="#configuration">Configuration</a> •
  <a href="ecosystem.md">Full Ecosystem Guide</a>
</p>

---

## Why Autoplex?

You have a structured plan with 20+ tasks across multiple phases. Running each manually means:

- Babysitting every session
- Losing context between tasks
- No quality gates between phases
- No retry when things fail

**Autoplex solves all of this.** It generates a bash script that:

```
loops through tasks → each runs as claude -p in a fresh session
→ detects failures → retries with adapted prompts → commits on success
→ runs cross-review audit after each phase → continues to next phase
```

**Production-proven**: 20+ tasks across 5 phases, ~$105 total cost, ~5 hours fully unattended, zero human intervention. Battle-tested across multiple real-world projects with complex multi-file migrations, refactors, and feature implementations.

## Quick Start

### Install

```bash
# Option 1: Copy to your skills directory
cp -r autoplex ~/.claude/skills/

# Option 2: Symlink
ln -s $(pwd) ~/.claude/skills/autoplex
```

### Use

In Claude Code, just say:

> _"I have a task plan. Run it autonomously."_

Or be more specific:

> _"Execute Phase 2-4 of my task plan overnight. Budget $12 per task."_

### Manual Usage

```bash
# Generate executor script (Claude Code does this for you via the skill)
# Then:
./scripts/executor.sh --dry-run          # Preview what will run
./scripts/executor.sh --skip-permissions  # Run fully unattended

# In tmux for background execution:
tmux new-session -d -s autoplex "zsh scripts/wrapper.sh"
tmux attach -t autoplex
```

## How It Works

### The 6-Step Per-Task Methodology

Every task runs in a completely fresh `claude -p` session — no context leakage between tasks:

| Step                      | What Happens                                 | Why It Matters                                              |
| ------------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| **1. Context Loading**    | Read task_plan.md, findings.md, progress.md  | Fresh session gets full context                             |
| **2. Research**           | Launch parallel Explore subagents (sonnet)   | Find all files, line numbers, patterns before touching code |
| **3. Implementation**     | Follow plan with anti-pattern awareness      | Systematic grep-then-replace, not memory-based              |
| **4. Verification**       | Run project's test/build suite               | Tests are specifications — fix code, not tests              |
| **5. Cross-Verification** | Parallel MCP audit (Codex + GemSuite)        | Independent AI review catches what you missed               |
| **6. Commit**             | Stage specific files, update progress ledger | Clean git history, trackable progress                       |

### Failure-Aware Retry

The executor doesn't just retry — it **adapts** based on what went wrong:

| Failure Type     | Detection            | Retry Adaptation                                     |
| ---------------- | -------------------- | ---------------------------------------------------- |
| Context overflow | `Prompt is too long` | Strip findings.md, fewer subagents, +$3 budget       |
| Rate limited     | `429`, `overloaded`  | Wait and retry normally                              |
| Budget exceeded  | `budget.*exceeded`   | Minimize cross-verification, +$5 budget              |
| API error        | `500`, `503`         | Retry normally (transient)                           |
| Generic          | Any non-zero exit    | Check git diff for partial work, continue from there |

### Phase-Level Quality Gates

After all tasks in a phase complete, a separate review session launches with:

- **Code review agent** — full quality/DRY/consistency check
- **Codex MCP** — type safety, import consistency, protocol correctness
- **GemSuite MCP** — component quality, edge cases, UX patterns
- **Full verification suite** — your project's test/build/lint pipeline

Reviews are quality gates, not blockers — task commits are already landed, so a review timeout won't lose work.

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

> **Note**: Codex and GemSuite MCPs are optional. Without them, autoplex falls back to self-review (read your own diff, check imports/consumers). See [ecosystem.md](ecosystem.md) for the full adaptation guide.

### Minimum Viable Setup

You need just three things:

1. A `task_plan.md` with phased tasks (any format — autoplex is flexible)
2. A `progress.md` with a status tracking table
3. A project verification command (`pnpm verify`, `npm test`, `cargo test`, etc.)

## Configuration

| Setting        | Default       | Notes                                     |
| -------------- | ------------- | ----------------------------------------- |
| Model          | opus          | Use sonnet for simple tasks to save cost  |
| Effort         | max           | High quality for autonomous execution     |
| Task timeout   | 2400s (40min) | Increase for very large tasks             |
| Review timeout | 2400s (40min) | Reviews with subagents often exceed 30min |
| Max retries    | 2             | 3 total attempts per task (1 + 2 retries) |
| Budget         | $6-18/task    | Scaled by complexity                      |

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

## Platform Gotchas (macOS)

These cost hours to discover. Saved here so you don't repeat them:

- **No `timeout` command** — uses background process + poll loop
- **bash 3.2** — no associative arrays, use `case` functions
- **`set -euo pipefail` + `grep`** — `grep -v` returns 1 when no matches; wrap with `|| true`
- **`CLAUDECODE` env var** — child `claude` processes refuse to start if set; wrapper must `unset` it
- **`claude -p` buffers output** — logs are empty until session ends; check `ps aux` instead
- **SIGTERM may not kill Claude** — escalate to `kill -9` after grace period
- **tmux PATH** — doesn't inherit parent shell; wrapper must source `~/.zshrc` and export PATH
- **Pipe exit codes** — `bash script | tee log` gives tee's exit code; use `${pipestatus[1]}`

## Origin

Born from necessity — a 25-task, 6-phase codebase migration that needed to run autonomously overnight. After manually running 5 tasks, the remaining 20 were executed entirely by this system with zero human intervention. The patterns, retry logic, and platform workarounds were all discovered and hardened through real production failures.

Since then, autoplex has been refined across multiple projects and codebases, evolving from a one-off script into a reusable skill that any Claude Code user can adopt.

See [ecosystem.md](ecosystem.md) for the full workflow context, companion tools, and adaptation guide.

## License

MIT
