# Autoplex Ecosystem

Autoplex doesn't operate in isolation. It's the execution layer of a broader workflow built on Claude Code skills, MCP servers, and development patterns. This document maps the full ecosystem so you can adopt the parts you need.

## The Workflow Pipeline

```
  Plan                    Execute                     Verify
  ────                    ───────                     ──────
  planning-with-files  →  autoplex                 →  code-review
  superpowers:plan        (this skill)                superpowers:verify
  sequential-thinking     6-step per-task method      codex + gemsuite MCPs
```

### Phase 1: Planning (upstream of autoplex)

Before autoplex can run, you need a structured task plan. These tools create it:

| Tool                                                                                | What It Does                                                                        | How Autoplex Uses It                                      |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **[planning-with-files](https://github.com/OthmanAdi/planning-with-files)**         | Creates `task_plan.md` + `progress.md` + `findings.md` in `.claude/plans/sessions/` | Autoplex reads these files as context for each task       |
| **[superpowers](https://github.com/obra/superpowers):writing-plans**                | Skill that guides Claude through structured plan creation                           | Produces the task_plan.md that autoplex consumes          |
| **[superpowers](https://github.com/obra/superpowers):brainstorming**                | Pre-planning creative exploration                                                   | Informs plan scope and approach before writing            |
| **[Sequential Thinking MCP](https://github.com/arben-adm/mcp-sequential-thinking)** | Step-by-step reasoning for complex architecture decisions                           | Used during plan creation for multi-file design decisions |

### Phase 2: Execution (autoplex itself)

During execution, each headless `claude -p` session uses these tools internally:

#### Subagent Types (launched by the headless session)

| Agent                           | Role                                                 | When Used                           |
| ------------------------------- | ---------------------------------------------------- | ----------------------------------- |
| `Explore` (sonnet)              | Codebase search — find files, line numbers, patterns | Step 2: Pre-Implementation Research |
| `code-reviewer` (opus)          | Full code quality review                             | Phase review Step 3                 |
| `build-error-resolver` (sonnet) | Fix build/test failures                              | When Step 4 verification fails      |

#### MCP Servers (used for cross-verification)

| MCP Server                                              | Tool ID                                         | Role in Autoplex                                                                                                                                                                                              | Link                                                 |
| ------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **Codex**                                               | `mcp__codex__codex`                             | Verify type safety, import consistency, protocol correctness. Used in Step 5 (per-task) and Phase Review Step 3.                                                                                              | —                                                    |
| **[GemSuite](https://github.com/PV-Bhat/gemsuite-mcp)** | `mcp__gemsuite-mcp__gem_process` / `gem_reason` | Review component quality, UX patterns, edge cases. `gem_process` for per-task review, `gem_reason` for deep phase review. **Note**: `file_path` param fails for `.ts`/`.tsx` — always pass `content` instead. | [GitHub](https://github.com/PV-Bhat/gemsuite-mcp)    |
| **[Context7](https://github.com/upstash/context7)**     | `mcp__context7__query-docs`                     | Look up library API docs when implementation touches framework APIs. Not used by default in autoplex prompts but available.                                                                                   | [GitHub](https://github.com/upstash/context7)        |
| **[Exa](https://github.com/exa-labs/exa-mcp-server)**   | `mcp__exa__web_search_exa`                      | Search for current best practices. Used in findings.md research phase (upstream).                                                                                                                             | [GitHub](https://github.com/exa-labs/exa-mcp-server) |

#### Companion Skills (used alongside autoplex)

| Skill                                          | When                                                  | Relationship                                                                                       |
| ---------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| **superpowers:executing-plans**                | Alternative to autoplex for in-session plan execution | Autoplex is the headless equivalent — use executing-plans for interactive, autoplex for unattended |
| **superpowers:verification-before-completion** | Before claiming work is done                          | Autoplex's Step 4 embeds this pattern                                                              |
| **superpowers:test-driven-development**        | TDD cycle within each task                            | The task prompt's Step 3 references TDD when applicable                                            |
| **session-start / session-end**                | Session lifecycle                                     | Autoplex replaces these — each task IS a session                                                   |
| **superpowers:dispatching-parallel-agents**    | Parallel independent work                             | Autoplex uses this pattern in Steps 2 and 5                                                        |

### Phase 3: Post-Execution Review

| Tool                                   | What It Does                                     |
| -------------------------------------- | ------------------------------------------------ |
| **superpowers:requesting-code-review** | Formal review of completed work                  |
| **code-review:code-review**            | PR-level code review                             |
| **pr-review-toolkit:review-pr**        | Multi-agent PR review with specialized reviewers |

---

## Competitive Landscape

### Why This Category Exists

The "autonomous plan execution" pattern emerged from a real need: developers create structured plans (PRDs, task lists, migration plans) but executing them manually across 10-20+ tasks is tedious. The solution is to loop `claude -p` with some form of progress tracking.

Every tool in this space answers the same question differently: **how much intelligence should live in the orchestrator vs. inside Claude?**

### The Spectrum

```
← Less orchestrator intelligence                    More orchestrator intelligence →

ralph          continuous-claude     ralphex          autoplex          ruflo/claude-flow
(87 lines)     (PR-per-iteration)    (Go pipeline)    (adaptive retry)  (enterprise swarm)
```

### Tool Categories

#### Simple Loops ("Ralph Pattern")

These tools run `claude -p` in a loop with minimal orchestration. Intelligence lives inside Claude.

| Tool                                                                     | Stars | Key Trait                                          | Limitation                                                  |
| ------------------------------------------------------------------------ | ----- | -------------------------------------------------- | ----------------------------------------------------------- |
| [ralph](https://github.com/snarktank/ralph)                              | 12.6k | Original pioneer, prd.json-driven                  | No failure detection, no phases, no retry adaptation        |
| [ralph-claude-code](https://github.com/frankbria/ralph-claude-code)      | 5.6k  | Circuit breaker (5 patterns), rate-limit awareness | Still single-loop, no multi-phase, no methodology injection |
| [continuous-claude](https://github.com/AnandChowdhary/continuous-claude) | 1.25k | PR-per-iteration, CI quality gate                  | No failure-type retry, no phases, loses WIP on crash        |
| [claude-pipeline](https://github.com/aaddrick/claude-pipeline)           | 93    | Drop-in `.claude/` directory                       | Limited orchestration logic                                 |
| [plangate](https://github.com/bishnubista/plangate)                      | 1     | PLAN.md-driven, build+review gates                 | Very early stage                                            |

#### Structured Executors

These add real orchestration: phases, review, crash recovery.

| Tool                                                                   | Stars | Key Trait                                                            | Limitation                                                                        |
| ---------------------------------------------------------------------- | ----- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| [ralphex](https://github.com/umputun/ralphex)                          | 726   | Go binary, 4-stage pipeline, Codex cross-review, stalemate detection | No failure-type retry, no per-task budget, no methodology injection               |
| [orchestration](https://github.com/lebed2045/orchestration)            | —     | Best quality gates (Gemini + isolated Claude), TDD enforcement       | **Single session** — crash = restart. No failure recovery. Context overflow risk. |
| [claude-orchestrator](https://github.com/reshashi/claude-orchestrator) | 64    | Full PR lifecycle automation, stall detection                        | Focused on delivery pipeline, not plan execution                                  |
| [orchestrator](https://github.com/gabrielkoerich/orchestrator)         | 4     | GitHub Issues as task backend, multi-CLI support                     | Early stage, limited quality gates                                                |

#### Enterprise Platforms

These are full multi-agent frameworks — different scale and complexity target.

| Tool                                                                   | Stars | Key Trait                                                        | Trade-off                                     |
| ---------------------------------------------------------------------- | ----- | ---------------------------------------------------------------- | --------------------------------------------- |
| [ruflo/claude-flow](https://github.com/ruvnet/ruflo)                   | 20.6k | 60+ specialized agents, vector memory, swarm topologies          | Massive infrastructure, enterprise complexity |
| [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)            | 40k   | Complete agile AI methodology, 12+ agent roles                   | Methodology framework, not an executable tool |
| [agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator) | 4.1k  | Parallel git worktrees, real-time dashboard, plugin architecture | Requires Composio ecosystem                   |
| [OpenSwarm](https://github.com/Intrect-io/OpenSwarm)                   | 211   | Linear issues + Discord + LanceDB vector memory                  | Tied to specific project management tools     |

#### SDK/Programmatic Approach

The alternative to shell scripts — using the Claude Agent SDK for programmatic control.

| Approach                                                                  | Strengths                                                 | Weaknesses                                                         |
| ------------------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------ |
| **[Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview)** | Structured I/O, native subagents, hooks, `max_budget_usd` | Proprietary license, 190MB Go binary, 6s cold start, model lock-in |
| **Shell scripts (autoplex)**                                              | Zero deps, full transparency, MIT license, battle-tested  | No structured streaming, manual timeout/budget implementation      |

See README.md's [Architectural Note](README.md#architectural-note-why-shell-scripts-not-agent-sdk) for the full rationale.

### Where Autoplex Fits

Autoplex occupies a unique position: **structured executor complexity with simple loop accessibility**.

It's the only tool that combines all five of these mechanisms:

1. **Failure-type-aware adaptive retry** (5 types × different prompt adaptations)
2. **Per-task methodology injection** (6-step methodology embedded in every prompt)
3. **Phase-level cross-review quality gates** (independent session + multi-agent)
4. **Crash-resumable progress tracking** (progress.md ledger)
5. **Per-task budget allocation with dynamic adjustment** (+$3/+$5 on retry)

No other tool implements all five. ralphex comes closest (has #3 and #4) but lacks #1, #2, and #5.

### What Autoplex Is NOT

- **Not a multi-agent swarm** — tasks run sequentially (parallelism is within each task via subagents)
- **Not an IDE plugin** — it's a CLI skill that generates and runs shell scripts
- **Not a framework** — you can't build other tools on top of it (use Agent SDK for that)
- **Not for single tasks** — use regular Claude Code for one-off work

---

## Key Patterns Referenced

### planning-with-files Convention

Autoplex expects this directory structure:

```
.claude/plans/sessions/{YYYY-MM-DD}-{name}/
├── task_plan.md       ← WHAT to build, phased tasks with IDs
├── progress.md        ← Cross-Reference Ledger (task status tracking)
├── findings.md        ← Research results (optional but recommended)
├── decisions/         ← ADR-style decision records (epics only)
└── handoff.md         ← Session handoff summary (epics only)
```

The Cross-Reference Ledger in `progress.md` uses this format:

```markdown
| Task | Status | Session | Notes                      |
| ---- | ------ | ------- | -------------------------- |
| T1   | DONE   | S1      | Completed, 5 files changed |
| T2   | TODO   |         |                            |
```

Autoplex uses `grep -qE "\| *${task_id} *\| *DONE"` to detect completed tasks and skip them.

### Commit Convention

The default commit format follows Conventional Commits:

```
<type>(<scope>): <task_id> — <description>
```

Examples:

```
refactor(auth): T3 — extract JWT validation into shared middleware
feat(api): T7 — add pagination to /users endpoint
fix(ui): Phase 2 review — missed import, lint compliance, type consistency
```

### Agent Output Gate

A critical pattern from the parent workflow: **never output conclusions while agents are running**. The task prompt enforces this in Steps 2 and 5 with explicit "Wait for ALL agents" instructions. Phase reviews have a "Do NOT write conclusions while agents are running" directive.

## Adapting for Your Project

### Minimum Viable Setup

You need:

1. A `task_plan.md` with phased tasks (any format — autoplex is flexible)
2. A `progress.md` with a status tracking table
3. A project verification command (`pnpm verify`, `npm test`, `cargo test`, etc.)

### Optional Enhancements

| Enhancement     | What It Adds                     | Worth It?                          |
| --------------- | -------------------------------- | ---------------------------------- |
| Codex MCP       | Type safety / logic verification | Yes for TypeScript/large codebases |
| GemSuite MCP    | AI-powered code review           | Yes for UI/component work          |
| findings.md     | Competitive analysis context     | Yes for greenfield features        |
| decisions/ ADRs | Decision audit trail             | Yes for multi-session epics        |

### Cross-Verification Without MCPs

If you don't have Codex/GemSuite, replace Step 5 with:

```
## Step 5: Self-Review
Review your own changes:
- Read every file you modified — check for consistency
- Run `git diff` and review each hunk
- Look for: broken imports, unused variables, style violations
- If changes touch shared code, grep for all consumers
```

This is less thorough but still useful as a pause-and-reflect checkpoint.
