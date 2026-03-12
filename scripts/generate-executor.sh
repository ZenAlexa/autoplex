#!/usr/bin/env bash
# =============================================================================
# Autoplex — Executor Script Template
# =============================================================================
# This is a TEMPLATE. The skill generates a project-specific version by
# replacing {PLACEHOLDER_NAME} markers with actual values.
#
# Usage:
#   ./scripts/{SCRIPT_NAME}.sh              # Run all remaining tasks
#   ./scripts/{SCRIPT_NAME}.sh --phase N    # Run specific phase only
#   ./scripts/{SCRIPT_NAME}.sh --task TX    # Run specific task only
#   ./scripts/{SCRIPT_NAME}.sh --dry-run    # Show what would run
#   ./scripts/{SCRIPT_NAME}.sh --resume TX  # Resume from TX (skip prior)
#
# Run in background (detached from terminal):
#   tmux new-session -d -s {SESSION} "zsh scripts/{WRAPPER_NAME}.sh"
#   tmux attach -t {SESSION}
#
# Prerequisites:
#   - claude CLI installed and authenticated
#   - In project root
#   - task_plan.md + progress.md exist in PLAN_DIR
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

PROJECT_DIR="{PROJECT_DIR}"
PLAN_DIR="{PLAN_DIR}"
LOG_DIR="{LOG_DIR}"
MODEL="opus"
EFFORT="max"
PERMISSION_MODE="auto"
MAX_RETRIES=2
RETRY_DELAY=15
TASK_TIMEOUT=2400       # 40 min per task
REVIEW_TIMEOUT=2400     # 40 min per review (reviews with subagents often run long)

# ─── Per-Task Budget (USD) — bash 3.2 compatible (no associative arrays) ────

get_task_budget() {
  case "$1" in
    # {BUDGET_CASES} — replace with project-specific entries, e.g.:
    # T1) echo 8 ;;   # Simple: description
    # T2) echo 15 ;;  # Complex: description
    *)   echo 10 ;;
  esac
}
REVIEW_BUDGET=10

# ─── Color output ────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_ok()    { echo -e "${GREEN}[  OK]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[FAIL]${NC}  $(date '+%H:%M:%S') $*"; }
log_phase() {
  echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  PHASE $1${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
}
log_review() {
  echo -e "\n${MAGENTA}────────────────────────────────────────────────────────────────${NC}"
  echo -e "${MAGENTA}  PHASE $1 — CROSS-REVIEW AUDIT${NC}"
  echo -e "${MAGENTA}────────────────────────────────────────────────────────────────${NC}\n"
}

# ─── Task Definitions ────────────────────────────────────────────────────────
# Format: PHASE:TASK_ID:DESCRIPTION

declare -a TASKS=(
  # {TASK_LIST} — replace with project-specific entries, e.g.:
  # "1:T1:Description of first task"
  # "1:T2:Description of second task"
  # "2:T3:Description of third task"
)

# ─── Prompt Templates ────────────────────────────────────────────────────────

generate_task_prompt() {
  local task_id="$1"
  local task_desc="$2"
  local phase="$3"

  cat <<'PROMPT_HEADER'
ultrathink

You are executing a single task from a multi-phase plan. This is a headless autonomous session — you must complete the task fully, verify, commit, and update progress without human interaction.

PROMPT_HEADER

  cat <<PROMPT_CONTEXT

## Your Task

**Phase ${phase} — ${task_id}: ${task_desc}**

## Step 1: Context Loading (MANDATORY — do this FIRST)

Read these files IN ORDER to understand the full context:

1. \`${PLAN_DIR}/task_plan.md\` — Find the **${task_id}** section. Read the ENTIRE section including all sub-tasks, verification steps, and special attention notes. Also read: "Execution Methodology", key decisions, and critical prerequisites.
2. \`${PLAN_DIR}/findings.md\` — Read research context and competitive baseline (if this file exists).
3. \`${PLAN_DIR}/progress.md\` — Check the Cross-Reference Ledger for task status and dependencies. Read session notes for any lessons from prior tasks.

## Step 2: Pre-Implementation Research

Use the Agent tool to launch **parallel research subagents** (subagent_type="Explore", model="sonnet"):

- **Agent 1**: Search the codebase for ALL files that ${task_id} needs to modify. Get exact line numbers and current patterns. Report counts.
- **Agent 2**: If the task references reference repos or external patterns, read those files to understand the approach.
- **Agent 3**: Check for any existing tests that cover the files being modified. Understand what the tests expect.

Wait for ALL agents to complete before proceeding. Cross-reference their findings.

## Step 3: Implementation

Follow the task plan's specific instructions. Apply these methodology rules:

**GOAL > PLAN**: The task description defines WHAT to build. The steps are suggestions. If you find a simpler path, take it. If line numbers have shifted, adapt silently.

**SYSTEMATIC REPLACEMENT**: For mechanical migrations, use grep to find ALL instances first, then replace methodically. Do NOT rely on memory — grep is truth.

**GLOBAL AWARENESS — LLM ANTI-PATTERNS TO AVOID**:
You are constrained by context window. This causes: (1) failure to reuse existing components, (2) creating redundant patterns, (3) spawning unnecessary new abstractions. Therefore:
- Before creating ANYTHING new, search if it already exists
- Prefer reusing existing patterns over inventing new ones
- If you modify shared code, trace ALL consumers
- Check imports — if you rename/move something, update all references

{PROJECT_SPECIFIC_CONTEXT}

**COMMIT DISCIPLINE**: Stage only files you intentionally changed. Use \`git diff --stat\` to verify before committing.

## Step 4: Verification (MANDATORY — do NOT skip)

Run the project verification command and ensure ALL checks pass:

\`\`\`bash
{VERIFY_COMMAND}
\`\`\`

If any test fails: the test is RIGHT until proven otherwise. Fix your code, not the test. Run \`git blame\` on the test to understand the specification before considering ANY test modification.

## Step 5: Cross-Verification (use subagents)

Launch these as **parallel Agent tool calls**:

{CROSS_VERIFY_STEPS}

Wait for ALL verification results. Fix any issues found. Re-verify if you made fixes.

## Step 6: Commit & Progress Update

1. **Commit**: \`git add <specific files>\` then commit with message format:
   \`{COMMIT_FORMAT}\`

2. **Update progress**: Edit \`${PLAN_DIR}/progress.md\`:
   - Update the Cross-Reference Ledger: change ${task_id} status to DONE, add session notes
   - Add a brief session entry with: files changed count, key changes, any deviations

PROMPT_CONTEXT
}

generate_review_prompt() {
  local phase="$1"

  cat <<'REVIEW_HEADER'
ultrathink

You are performing a Phase-level cross-review audit. This is a quality gate — nothing proceeds until you verify everything is correct. Be thorough and uncompromising.

REVIEW_HEADER

  cat <<REVIEW_BODY

## Phase ${phase} Cross-Review Audit

### Step 1: Context Loading

1. Read \`${PLAN_DIR}/task_plan.md\` — understand ALL Phase ${phase} task goals and targets
2. Read \`${PLAN_DIR}/progress.md\` — see what was done in each task, any noted deviations
3. Read \`${PLAN_DIR}/findings.md\` — baseline context (if exists)

### Step 2: Gather Changes

Run: \`git log --oneline --since="8 hours ago"\` to identify Phase ${phase} commits.
Run: \`git diff <first-phase-commit>~1..HEAD --stat\` to see all changed files.
Read each changed file to understand the full scope.

### Step 3: Launch Parallel Review Agents

Use the Agent tool to launch ALL of these in parallel:

1. **Code Review Agent** (subagent_type="code-reviewer"):
   "Review all files changed in Phase ${phase}. Check: code quality, DRY principle, proper abstraction, pattern consistency, no regressions."

{REVIEW_CROSS_VERIFY_STEPS}

3. **Full Verification**: Run the project verification command.

**WAIT** for ALL agents/commands to complete. Do NOT write conclusions while agents are running.

### Step 4: Cross-Reference Findings

After all agents complete, analyze their results:
- List every issue found, categorized by severity (critical/warning/info)
- For each issue: file, line, description, fix recommendation
- Note any CONTRADICTIONS between agents — investigate and resolve

### Step 5: Fix Issues

- Fix ALL critical and warning issues immediately
- Re-verify after fixes
- If fixes are substantial, run another round of verification on the fixed files

### Step 6: Commit & Report

1. If fixes were made: \`git commit -m "{REVIEW_COMMIT_FORMAT}"\`
2. Update \`${PLAN_DIR}/progress.md\` with review results:
   - Phase ${phase} review status: PASSED/FAILED
   - Issues found and fixed (count by severity)
   - Confidence level for proceeding to next phase

REVIEW_BODY
}

# ─── Core Execution ──────────────────────────────────────────────────────────

check_log_for_issues() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then echo "no_log"; return; fi

  # Context overflow (includes "Prompt is too long" from claude -p)
  if grep -qi "context.*window\|context.*limit\|token.*limit\|too many tokens\|context.*exceeded\|conversation.*too.*long\|context.*compress\|Prompt is too long" "$log_file" 2>/dev/null; then
    echo "context_overflow"; return
  fi
  # Rate limiting
  if grep -qi "rate.*limit\|429\|too many requests\|overloaded" "$log_file" 2>/dev/null; then
    echo "rate_limited"; return
  fi
  # API errors (transient)
  if grep -qi "api.*error\|internal.*server.*error\|500\|503\|connection.*refused" "$log_file" 2>/dev/null; then
    echo "api_error"; return
  fi
  # Budget exhaustion
  if grep -qi "budget.*exceeded\|budget.*limit\|max.*budget" "$log_file" 2>/dev/null; then
    echo "budget_exceeded"; return
  fi
  echo "ok"
}

run_claude() {
  local prompt="$1" budget="$2" label="$3" log_file="$4" timeout_secs="$5"

  log_info "Running: ${label}"
  log_info "Budget: \$${budget} | Model: ${MODEL} | Effort: ${EFFORT} | Timeout: ${timeout_secs}s"
  log_info "Log: ${log_file}"

  local start_time; start_time=$(date +%s)

  # Write prompt to temp file (reliable for long prompts — avoids pipe truncation)
  local prompt_file; prompt_file=$(mktemp "${TMPDIR:-/tmp}/claude-prompt-XXXXXX.md")
  printf '%s' "$prompt" > "$prompt_file"

  local exit_code=0

  # Background + manual timeout (macOS has no timeout command)
  claude -p \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --max-budget-usd "$budget" \
    --permission-mode "$PERMISSION_MODE" \
    --verbose \
    < "$prompt_file" \
    > "$log_file" 2>&1 &
  local claude_pid=$!

  local elapsed=0
  while kill -0 "$claude_pid" 2>/dev/null; do
    if [[ $elapsed -ge $timeout_secs ]]; then
      # Graceful shutdown: SIGTERM first, then SIGKILL after 10s grace period
      kill "$claude_pid" 2>/dev/null || true
      sleep 10
      if kill -0 "$claude_pid" 2>/dev/null; then
        kill -9 "$claude_pid" 2>/dev/null || true
      fi
      wait "$claude_pid" 2>/dev/null || true
      exit_code=124  # Same as GNU timeout
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  if [[ $exit_code -ne 124 ]]; then
    wait "$claude_pid" 2>/dev/null
    exit_code=$?
  fi

  rm -f "$prompt_file"

  local end_time; end_time=$(date +%s)
  local duration=$(( end_time - start_time ))
  local minutes=$(( duration / 60 )) seconds=$(( duration % 60 ))

  if [[ "$exit_code" -eq 0 ]]; then
    log_ok "${label} completed in ${minutes}m${seconds}s"; return 0
  elif [[ "$exit_code" -eq 124 ]]; then
    log_error "${label} TIMED OUT after ${minutes}m${seconds}s (limit: ${timeout_secs}s)"; return 124
  else
    log_error "${label} FAILED (exit ${exit_code}) after ${minutes}m${seconds}s"; return "$exit_code"
  fi
}

run_task_with_retry() {
  local phase="$1" task_id="$2" task_desc="$3"
  local max_attempts=$((MAX_RETRIES + 1))

  local budget
  if [[ -n "${BUDGET_OVERRIDE:-}" ]]; then budget="$BUDGET_OVERRIDE"
  else budget="$(get_task_budget "$task_id")"; fi
  local attempt=0 prev_log_file=""

  while [[ $attempt -lt $max_attempts ]]; do
    attempt=$((attempt + 1))
    local suffix=""; [[ $attempt -gt 1 ]] && suffix="_retry${attempt}"
    local log_file="${LOG_DIR}/phase${phase}_${task_id}${suffix}_$(date '+%Y%m%d_%H%M%S').log"

    local prompt
    if [[ $attempt -eq 1 ]]; then
      prompt=$(generate_task_prompt "$task_id" "$task_desc" "$phase")
    else
      local prev_issue; prev_issue=$(check_log_for_issues "$prev_log_file")
      local retry_preamble=""
      case "$prev_issue" in
        context_overflow)
          retry_preamble="## RETRY NOTE (attempt ${attempt}/${max_attempts})
Previous attempt ran out of context window. This time:
- Be MORE CONCISE — skip verbose explanations
- Fewer subagents — do research sequentially if needed
- Skip findings.md — the task plan has all you need
"
          budget=$((budget + 3)) ;;
        rate_limited)
          retry_preamble="## RETRY NOTE (attempt ${attempt}/${max_attempts})
Previous attempt hit rate limits. Proceeding normally.
" ;;
        budget_exceeded)
          retry_preamble="## RETRY NOTE (attempt ${attempt}/${max_attempts})
Previous attempt exceeded budget. Be more efficient:
- Skip verbose cross-verification — one check is sufficient
- Minimize file reads — only files you will modify
- Mechanical work first, verify once at the end
"
          budget=$((budget + 5)) ;;
        *)
          retry_preamble="## RETRY NOTE (attempt ${attempt}/${max_attempts})
Previous attempt failed. Check git status for partial work.
Run \`git diff --stat\` first to see what was already changed.
" ;;
      esac
      prompt="${retry_preamble}
$(generate_task_prompt "$task_id" "$task_desc" "$phase")"
    fi

    log_info "Attempt ${attempt}/${max_attempts} for ${task_id}"

    if run_claude "$prompt" "$budget" "Phase ${phase} ${task_id}: ${task_desc}" "$log_file" "$TASK_TIMEOUT"; then
      local issue; issue=$(check_log_for_issues "$log_file")
      if [[ "$issue" != "ok" && "$issue" != "no_log" ]]; then
        log_warn "${task_id} completed but log shows: ${issue}"
      fi
      return 0
    fi

    prev_log_file="$log_file"
    local issue; issue=$(check_log_for_issues "$log_file")
    log_warn "${task_id} failed (issue: ${issue}). ${attempt}/${max_attempts} attempts used."

    if [[ $attempt -lt $max_attempts ]]; then
      local dirty_files
      dirty_files=$(cd "$PROJECT_DIR" && git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$dirty_files" -gt 0 ]]; then
        log_warn "Found ${dirty_files} uncommitted changes — preserving for retry"
      fi
      log_info "Waiting ${RETRY_DELAY}s before retry..."
      sleep "$RETRY_DELAY"
    fi
  done

  log_error "${task_id} FAILED after ${max_attempts} attempts"
  return 1
}

run_phase_review() {
  local phase="$1"
  local prompt; prompt=$(generate_review_prompt "$phase")
  local log_file="${LOG_DIR}/phase${phase}_REVIEW_$(date '+%Y%m%d_%H%M%S').log"

  log_review "$phase"

  if run_claude "$prompt" "$REVIEW_BUDGET" "Phase ${phase} Cross-Review Audit" "$log_file" "$REVIEW_TIMEOUT"; then
    log_ok "Phase ${phase} review PASSED"; return 0
  else
    local issue; issue=$(check_log_for_issues "$log_file")
    log_warn "Phase ${phase} review completed with issues: ${issue}"
    # Review failures are warnings, not blockers — task commits are already landed
    return 0
  fi
}

# ─── Pre-Flight Checks ──────────────────────────────────────────────────────

preflight() {
  log_info "Pre-flight checks..."

  # Verify project directory
  if [[ ! -d "$PROJECT_DIR" ]]; then
    log_error "Project directory not found: $PROJECT_DIR"; exit 1
  fi

  # Verify claude CLI
  if ! command -v claude &>/dev/null; then
    log_error "claude CLI not found. Install: curl -fsSL https://claude.ai/install.sh | bash"; exit 1
  fi

  # Verify plan files
  for f in task_plan.md progress.md; do
    if [[ ! -f "$PLAN_DIR/$f" ]]; then
      log_error "Missing plan file: $PLAN_DIR/$f"; exit 1
    fi
  done

  # Check for uncommitted changes
  local dirty
  dirty=$(cd "$PROJECT_DIR" && git status --porcelain 2>/dev/null | { grep -v '^??' || true; } | wc -l | tr -d ' ')
  if [[ "$dirty" -gt 0 ]]; then
    log_warn "Working tree has ${dirty} uncommitted changes"
    log_warn "Recommend: commit or stash before running autonomous tasks"
  fi

  log_ok "Pre-flight checks passed"
}

# ─── Notification (macOS) ────────────────────────────────────────────────────

notify() {
  local title="$1" message="$2"
  # macOS notification (silent fail on other platforms)
  osascript -e "display notification \"${message}\" with title \"${title}\"" 2>/dev/null || true
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

FILTER_PHASE="" FILTER_TASK="" RESUME_FROM="" DRY_RUN=false BUDGET_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --phase)  FILTER_PHASE="$2"; shift 2 ;;
    --task)   FILTER_TASK="$2"; shift 2 ;;
    --resume) RESUME_FROM="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --budget) BUDGET_OVERRIDE="$2"; shift 2 ;;
    --skip-permissions) PERMISSION_MODE="bypassPermissions"; shift ;;
    --model)  MODEL="$2"; shift 2 ;;
    --help)
      cat <<HELP
Autonomous Plan Executor

Usage: $0 [OPTIONS]

Options:
  --phase N              Run specific phase only
  --task TX              Run specific task only
  --resume TX            Resume from task TX (skip all prior tasks)
  --dry-run              Show what would run without executing
  --budget N             Override budget for single task (USD)
  --skip-permissions     Bypass all permission prompts (fully unattended)
  --model MODEL          Override model (opus, sonnet)
  --help                 Show this help

Examples:
  $0                           # Run all tasks with phase reviews
  $0 --phase 1                 # Run only Phase 1 tasks + review
  $0 --task T1                 # Run only T1
  $0 --resume T5              # Skip tasks before T5
  $0 --skip-permissions        # Fully unattended mode
  $0 --dry-run                 # Preview execution plan
HELP
      exit 0 ;;
    *) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
  esac
done

# ─── Main Loop ───────────────────────────────────────────────────────────────

main() {
  cd "$PROJECT_DIR"
  mkdir -p "$LOG_DIR"

  if [[ "$DRY_RUN" != true ]]; then preflight; fi

  echo ""
  log_info "Autonomous Plan Executor"
  log_info "Project: ${PROJECT_DIR}"
  log_info "Model: ${MODEL} | Effort: ${EFFORT} | Permission: ${PERMISSION_MODE}"
  log_info "Task timeout: ${TASK_TIMEOUT}s | Review timeout: ${REVIEW_TIMEOUT}s | Retries: ${MAX_RETRIES}"

  # Calculate total budget (dynamic phase count)
  local total_budget=0
  local tb_phase tb_id tb_desc num_phases=0 prev_phase=""
  for entry in "${TASKS[@]}"; do
    IFS=':' read -r tb_phase tb_id tb_desc <<< "$entry"
    total_budget=$((total_budget + $(get_task_budget "$tb_id")))
    [[ "$tb_phase" != "$prev_phase" ]] && num_phases=$((num_phases + 1)) && prev_phase="$tb_phase"
  done
  total_budget=$((total_budget + REVIEW_BUDGET * num_phases))
  log_info "Estimated max budget: \$${total_budget} (tasks + ${num_phases} phase reviews)"

  [[ -n "$FILTER_TASK" ]]  && log_info "Filter: task=${FILTER_TASK}"
  [[ -n "$FILTER_PHASE" ]] && log_info "Filter: phase=${FILTER_PHASE}"
  [[ -n "$RESUME_FROM" ]]  && log_info "Resume from: ${RESUME_FROM}"
  echo ""

  local current_phase="" phase_has_tasks=false
  local total_tasks=0 completed_tasks=0 skipped_tasks=0 failed_tasks=0
  local reached_resume=false
  [[ -z "$RESUME_FROM" ]] && reached_resume=true

  for entry in "${TASKS[@]}"; do
    IFS=':' read -r phase task_id task_desc <<< "$entry"

    if [[ "$reached_resume" == false ]]; then
      if [[ "$task_id" == "$RESUME_FROM" ]]; then reached_resume=true
      else log_info "Skipping ${task_id} (before resume point)"; skipped_tasks=$((skipped_tasks + 1)); continue; fi
    fi

    [[ -n "$FILTER_TASK" && "$task_id" != "$FILTER_TASK" ]] && continue
    [[ -n "$FILTER_PHASE" && "$phase" != "$FILTER_PHASE" ]] && continue

    if [[ "$phase" != "$current_phase" ]]; then
      if [[ "$phase_has_tasks" == true && -z "$FILTER_TASK" && "$failed_tasks" -eq 0 ]]; then
        if [[ "$DRY_RUN" == true ]]; then log_info "[DRY RUN] Would run Phase ${current_phase} cross-review (\$${REVIEW_BUDGET})"
        else run_phase_review "$current_phase"; notify "Phase ${current_phase} Complete" "Starting Phase ${phase}..."; fi
      fi
      current_phase="$phase"; phase_has_tasks=false; log_phase "$phase"
    fi

    total_tasks=$((total_tasks + 1)); phase_has_tasks=true
    local task_budget; task_budget=$(get_task_budget "$task_id")

    if [[ "$DRY_RUN" == true ]]; then
      log_info "[DRY RUN] Would run: Phase ${phase} ${task_id}: ${task_desc} (\$${task_budget})"; continue
    fi

    if grep -qE "\| *${task_id} *\| *DONE" "$PLAN_DIR/progress.md" 2>/dev/null; then
      log_ok "${task_id} already DONE — skipping"; completed_tasks=$((completed_tasks + 1)); continue
    fi

    if run_task_with_retry "$phase" "$task_id" "$task_desc"; then
      completed_tasks=$((completed_tasks + 1))
      log_ok "${task_id} done (${completed_tasks}/${total_tasks} tasks)"
      notify "${task_id} Complete" "${task_desc}"
    else
      failed_tasks=$((failed_tasks + 1))
      log_error "${task_id} FAILED after all retries!"
      log_error "Resume with: $0 --resume ${task_id}"
      notify "FAILURE: ${task_id}" "Task failed. Check logs."
      break
    fi
    sleep 5
  done

  if [[ "$phase_has_tasks" == true && -z "$FILTER_TASK" && "$DRY_RUN" != true && "$failed_tasks" -eq 0 ]]; then
    run_phase_review "$current_phase"
  fi

  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  EXECUTION SUMMARY${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  log_info "Total tasks:     ${total_tasks}"
  [[ "$skipped_tasks" -gt 0 ]] && log_info "Skipped (resume): ${skipped_tasks}"
  log_ok   "Completed:       ${completed_tasks}"
  [[ "$failed_tasks" -gt 0 ]] && log_error "Failed:          ${failed_tasks}"
  log_info "Logs:            ${LOG_DIR}/"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

  if [[ "$failed_tasks" -eq 0 && "$DRY_RUN" != true ]]; then
    notify "Plan Complete" "All tasks finished successfully!"
    log_ok "All tasks completed successfully!"
  fi

  return "$failed_tasks"
}

main
