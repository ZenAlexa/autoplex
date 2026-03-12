# Autoplex

**Autonomous multi-phase plan execution for Claude Code.**

Run complex task plans unattended — each task gets a fresh `claude -p` headless session with full methodology (research subagents → implementation → verification → cross-verification → commit), failure-aware retry, and phase-level quality gate reviews. Runs in tmux while you sleep.

## What It Does

You have a `task_plan.md` with 20 phased tasks. Instead of running each manually:

```
autoplex generates a bash script → loops through tasks → each runs as claude -p
→ detects failures → retries with adapted prompts → commits on success
→ runs cross-review audit after each phase → continues to next phase
```

**Battle-tested**: 16 tasks across 5 phases, ~$105 budget, ~5 hours unattended, zero human intervention needed.

## Quick Start

### Install as Claude Code Skill

```bash
# Copy to your skills directory
cp -r autoplex ~/.claude/skills/

# Or symlink
ln -s $(pwd)/autoplex ~/.claude/skills/autoplex
```

Then in Claude Code, say: _"I have a task plan. Run it autonomously."_

### Manual Usage

```bash
# Generate executor script (Claude Code does this for you via the skill)
# Then:
./scripts/executor.sh --dry-run          # Preview
./scripts/executor.sh --skip-permissions  # Run unattended

# In tmux for background execution:
tmux new-session -d -s autoplex "zsh scripts/wrapper.sh"
tmux attach -t autoplex
```

## How It Works

### Per-Task Flow (6-Step Methodology)

Each task runs in a completely fresh `claude -p` session:

1. **Context Loading** — Read task_plan.md, findings.md, progress.md
2. **Research** — Launch parallel Explore subagents to scan codebase
3. **Implementation** — Follow plan with anti-pattern awareness
4. **Verification** — Run project's test/build suite
5. **Cross-Verification** — Codex MCP + GemSuite MCP parallel audit
6. **Commit** — Stage specific files, commit, update progress ledger

### Failure-Aware Retry

| Failure Type     | Detection Pattern    | Retry Adaptation                    |
| ---------------- | -------------------- | ----------------------------------- |
| Context overflow | `Prompt is too long` | Strip findings.md, fewer subagents  |
| Rate limited     | `429`, `overloaded`  | Wait and retry normally             |
| Budget exceeded  | `budget.*exceeded`   | Reduce cross-verification, +$5      |
| API error        | `500`, `503`         | Retry normally (transient)          |
| Generic          | Any non-zero exit    | Check git diff, continue from there |

### Phase-Level Quality Gates

After all tasks in a phase complete, a separate review session launches:

- Code review agent (code-reviewer subagent)
- Codex MCP verification (type safety, imports, consistency)
- GemSuite MCP deep review (quality, edge cases, patterns)
- Full project verification suite

## Configuration

| Setting        | Default       | Notes                                 |
| -------------- | ------------- | ------------------------------------- |
| Model          | opus          | Use sonnet for simple tasks           |
| Effort         | max           | High quality for autonomous execution |
| Task timeout   | 2400s (40min) | Increase for very large tasks         |
| Review timeout | 2400s (40min) | Reviews run long due to subagents     |
| Max retries    | 2             | 3 total attempts (1 + 2 retries)      |
| Budget         | $6-18/task    | Scaled by complexity                  |

## File Structure

```
autoplex/
├── SKILL.md                          # Claude Code skill definition (346 lines)
├── README.md                         # This file
├── ecosystem.md                      # Companion skills, MCPs, and workflow patterns
├── scripts/
│   └── generate-executor.sh          # Bash script template (602 lines)
└── references/
    └── production-learnings.md       # Real-world gotchas and timing data
```

## Requirements

- **Claude Code** (`claude` CLI) installed and authenticated
- **tmux** for background execution
- A task plan following the [planning-with-files](https://github.com/OthmanAdi/planning-with-files) pattern
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

Built during the XAgent Design System Unification — a 25-task, 6-phase migration that needed to run autonomously overnight. After manually running 5 tasks, the remaining 16 were executed entirely by this system with zero human intervention.

See [ecosystem.md](ecosystem.md) for the full workflow context and companion tools.

## License

MIT
