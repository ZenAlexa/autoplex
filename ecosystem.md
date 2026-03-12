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

| Tool                                                                         | What It Does                                                                        | How Autoplex Uses It                                      |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **[planning-with-files](https://github.com/OthmanAdi/planning-with-files)**  | Creates `task_plan.md` + `progress.md` + `findings.md` in `.claude/plans/sessions/` | Autoplex reads these files as context for each task       |
| **superpowers:writing-plans**                                                | Skill that guides Claude through structured plan creation                           | Produces the task_plan.md that autoplex consumes          |
| **superpowers:brainstorming**                                                | Pre-planning creative exploration                                                   | Informs plan scope and approach before writing            |
| **Sequential Thinking MCP** (`mcp__sequential-thinking__sequentialthinking`) | Step-by-step reasoning for complex architecture decisions                           | Used during plan creation for multi-file design decisions |

### Phase 2: Execution (autoplex itself)

During execution, each headless `claude -p` session uses these tools internally:

#### Subagent Types (launched by the headless session)

| Agent                           | Role                                                 | When Used                           |
| ------------------------------- | ---------------------------------------------------- | ----------------------------------- |
| `Explore` (sonnet)              | Codebase search — find files, line numbers, patterns | Step 2: Pre-Implementation Research |
| `code-reviewer` (opus)          | Full code quality review                             | Phase review Step 3                 |
| `build-error-resolver` (sonnet) | Fix build/test failures                              | When Step 4 verification fails      |

#### MCP Servers (used for cross-verification)

| MCP Server   | Tool ID                                         | Role in Autoplex                                                                                                                                                                                              |
| ------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Codex**    | `mcp__codex__codex`                             | Verify type safety, import consistency, protocol correctness. Used in Step 5 (per-task) and Phase Review Step 3.                                                                                              |
| **GemSuite** | `mcp__gemsuite-mcp__gem_process` / `gem_reason` | Review component quality, UX patterns, edge cases. `gem_process` for per-task review, `gem_reason` for deep phase review. **Note**: `file_path` param fails for `.ts`/`.tsx` — always pass `content` instead. |
| **Context7** | `mcp__context7__query-docs`                     | Look up library API docs when implementation touches framework APIs. Not used by default in autoplex prompts but available.                                                                                   |
| **Exa**      | `mcp__exa__web_search_exa`                      | Search for current best practices. Used in findings.md research phase (upstream).                                                                                                                             |

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

Examples from production:

```
refactor(ui): T6 — simplify radius/shadow syntax across codebase
refactor(ui): T14 — migrate pages/settings/ to semantic design tokens
fix(ui): Phase 4 review — missed migration, lint compliance, token consistency
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
