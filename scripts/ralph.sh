#!/bin/bash
# Ralph — autonomous AI agent loop
#
# Picks the oldest ralph:todo issue in a milestone, spawns a fresh
# agent instance to implement it, then repeats until done.
#
# Usage: ./scripts/ralph.sh --milestone <name> [max_iterations]

set -e

# ── Parse arguments ──────────────────────────────────────────────

MILESTONE=""
MAX_ITERATIONS=10
TOOL_COMMAND="claude"
TOOL_ARGS="--dangerously-skip-permissions --print"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKING_PATH="$(pwd)"
PROGRESS_FILE="$WORKING_PATH/progress.txt"

while [[ $# -gt 0 ]]; do
  case $1 in
    --milestone)   MILESTONE="$2";        shift 2 ;;
    --milestone=*) MILESTONE="${1#*=}";    shift   ;;
    *)
      # Bare number = max iterations
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$MILESTONE" ]]; then
  echo "Error: --milestone <name> is required."
  echo "Usage: ./scripts/ralph.sh --milestone <name> [max_iterations]"
  exit 1
fi

# ── Preflight checks ────────────────────────────────────────────

if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI not found. Install it: https://cli.github.com"
  exit 1
fi

if ! gh repo view --json name &> /dev/null; then
  echo "Error: Not in a GitHub repository or not authenticated with gh."
  exit 1
fi

# ── Create labels (idempotent) ───────────────────────────────────

echo "Ensuring Ralph labels exist..."
gh label create "ralph:todo"        --color "5319E7" --description "Story not started"     --force 2>/dev/null || true
gh label create "ralph:in-progress" --color "FBCA04" --description "Agent working on story" --force 2>/dev/null || true
gh label create "ralph:done"        --color "0E8A16" --description "Story completed"        --force 2>/dev/null || true
gh label create "ralph:failed"      --color "D93F0B" --description "Story failed"           --force 2>/dev/null || true

# ── Verify milestone exists ──────────────────────────────────────

MILESTONE_COUNT=$(gh api repos/{owner}/{repo}/milestones \
  --jq "[.[] | select(.title == \"$MILESTONE\")] | length" 2>/dev/null || echo "0")

if [[ "$MILESTONE_COUNT" -eq 0 ]]; then
  echo "Error: Milestone '$MILESTONE' not found. Run /ralph-github first to create it."
  exit 1
fi

# ── Set up branch ────────────────────────────────────────────────
# Branch name derived from milestone: "My Feature" → "ralph/my-feature"

BRANCH="ralph/$(echo "$MILESTONE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
CURRENT_BRANCH=$(git branch --show-current)

if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Checking out existing branch: $BRANCH"
    git checkout "$BRANCH"
  else
    echo "Creating new branch: $BRANCH"
    git checkout -b "$BRANCH" main
  fi
fi

# ── Initialize progress file ────────────────────────────────────

if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log"    > "$PROGRESS_FILE"
  echo "Milestone: $MILESTONE"  >> "$PROGRESS_FILE"
  echo "Started: $(date)"       >> "$PROGRESS_FILE"
  echo "---"                    >> "$PROGRESS_FILE"
fi

# ── Report milestone issues ───────────────────────────────────────

echo ""
echo "Milestone: $MILESTONE"
echo "---------------------------------------------------------------"

TODO_ISSUES=$(gh issue list --milestone "$MILESTONE" --label "ralph:todo" --json number,title --jq '.[] | "  [ ] #\(.number) \(.title)"' 2>/dev/null || true)
DONE_ISSUES=$(gh issue list --milestone "$MILESTONE" --label "ralph:done" --json number,title --jq '.[] | "  [x] #\(.number) \(.title)"' 2>/dev/null || true)
IN_PROGRESS_ISSUES=$(gh issue list --milestone "$MILESTONE" --label "ralph:in-progress" --json number,title --jq '.[] | "  [~] #\(.number) \(.title)"' 2>/dev/null || true)
FAILED_ISSUES=$(gh issue list --milestone "$MILESTONE" --label "ralph:failed" --json number,title --jq '.[] | "  [!] #\(.number) \(.title)"' 2>/dev/null || true)

TODO_COUNT=$(echo "$TODO_ISSUES" | grep -c '#' 2>/dev/null || echo "0")
DONE_COUNT=$(echo "$DONE_ISSUES" | grep -c '#' 2>/dev/null || echo "0")
IN_PROGRESS_COUNT=$(echo "$IN_PROGRESS_ISSUES" | grep -c '#' 2>/dev/null || echo "0")
FAILED_COUNT=$(echo "$FAILED_ISSUES" | grep -c '#' 2>/dev/null || echo "0")
TOTAL=$((TODO_COUNT + DONE_COUNT + IN_PROGRESS_COUNT + FAILED_COUNT))

[[ -n "$DONE_ISSUES" ]]        && echo "$DONE_ISSUES"
[[ -n "$IN_PROGRESS_ISSUES" ]] && echo "$IN_PROGRESS_ISSUES"
[[ -n "$TODO_ISSUES" ]]        && echo "$TODO_ISSUES"
[[ -n "$FAILED_ISSUES" ]]      && echo "$FAILED_ISSUES"

echo "---------------------------------------------------------------"
echo "Total: $TOTAL | Done: $DONE_COUNT | Todo: $TODO_COUNT | In-progress: $IN_PROGRESS_COUNT | Failed: $FAILED_COUNT"
echo ""

# ── Main loop ────────────────────────────────────────────────────

echo "Starting Ralph - Branch: $BRANCH - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # Pick the oldest ralph:todo issue in this milestone
  ISSUE_JSON=$(gh issue list \
    --milestone "$MILESTONE" \
    --label "ralph:todo" \
    --sort created \
    --json number,title,body \
    --limit 1 2>/dev/null || echo "[]")

  ISSUE_NUMBER=$(echo "$ISSUE_JSON" | jq -r '.[0].number // empty')

  # Nothing to do — either we're done, or stuck issues need a retry
  if [[ -z "$ISSUE_NUMBER" ]]; then
    IN_PROGRESS=$(gh issue list \
      --milestone "$MILESTONE" \
      --label "ralph:in-progress" \
      --json number --jq 'length' 2>/dev/null || echo "0")

    if [[ "$IN_PROGRESS" -gt 0 ]]; then
      echo "No ralph:todo issues, but $IN_PROGRESS still in-progress. Resetting for retry..."
      gh issue list --milestone "$MILESTONE" --label "ralph:in-progress" \
        --json number --jq '.[].number' | while read -r num; do
        gh issue edit "$num" --remove-label "ralph:in-progress" --add-label "ralph:todo" 2>/dev/null || true
      done
      continue
    fi

    echo ""
    echo "Ralph completed all tasks! No remaining ralph:todo issues."
    exit 0
  fi

  ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.[0].title')
  ISSUE_BODY=$(echo "$ISSUE_JSON"  | jq -r '.[0].body')

  echo "Working on: #$ISSUE_NUMBER - $ISSUE_TITLE"

  # Mark as in-progress so other instances don't pick it up
  gh issue edit "$ISSUE_NUMBER" --remove-label "ralph:todo" --add-label "ralph:in-progress" 2>/dev/null || true

  # Build prompt: ralph.md instructions + issue context (use temp file to avoid shell escaping issues)
  PROMPT_FILE=$(mktemp)
  trap "rm -f '$PROMPT_FILE'" EXIT
  cat "$SCRIPT_DIR/ralph.md" > "$PROMPT_FILE"
  cat >> "$PROMPT_FILE" <<ISSUE_EOF

---

## Current Issue

**Issue:** #$ISSUE_NUMBER - $ISSUE_TITLE
**Branch:** $BRANCH
**Milestone:** $MILESTONE

$ISSUE_BODY
ISSUE_EOF

  # Spawn a fresh Claude Code instance for this issue
  OUTPUT=$($TOOL_COMMAND $TOOL_ARGS < "$PROMPT_FILE" 2>&1 | tee /dev/stderr) || true
  rm -f "$PROMPT_FILE"

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

# ── Max iterations reached ───────────────────────────────────────

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS)."
echo "Check milestone progress: gh issue list --milestone \"$MILESTONE\""
exit 1
