#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh --milestone <name> [max_iterations]

set -e

# Parse arguments
MILESTONE=""
MAX_ITERATIONS=10
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"

while [[ $# -gt 0 ]]; do
  case $1 in
    --milestone)
      MILESTONE="$2"
      shift 2
      ;;
    --milestone=*)
      MILESTONE="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$MILESTONE" ]]; then
  echo "Error: --milestone <name> is required."
  echo "Usage: ./ralph.sh --milestone <name> [max_iterations]"
  exit 1
fi

# Ensure gh CLI is available
if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI not found. Install it: https://cli.github.com"
  exit 1
fi

# Ensure we're in a git repo with a GitHub remote
if ! gh repo view --json name &> /dev/null; then
  echo "Error: Not in a GitHub repository or not authenticated with gh."
  exit 1
fi

# Create labels if they don't exist
echo "Ensuring Ralph labels exist..."
gh label create "ralph:todo" --color "5319E7" --description "Story not started" --force 2>/dev/null || true
gh label create "ralph:in-progress" --color "FBCA04" --description "Agent working on story" --force 2>/dev/null || true
gh label create "ralph:done" --color "0E8A16" --description "Story completed" --force 2>/dev/null || true
gh label create "ralph:failed" --color "D93F0B" --description "Story failed" --force 2>/dev/null || true

# Verify milestone exists
MILESTONE_COUNT=$(gh api repos/{owner}/{repo}/milestones --jq "[.[] | select(.title == \"$MILESTONE\")] | length" 2>/dev/null || echo "0")
if [[ "$MILESTONE_COUNT" -eq 0 ]]; then
  echo "Error: Milestone '$MILESTONE' not found. Run the /ralph skill first to create it."
  exit 1
fi

# Derive branch name from milestone
BRANCH="ralph/$(echo "$MILESTONE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

# Create or checkout branch
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

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Milestone: $MILESTONE" >> "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Milestone: $MILESTONE - Branch: $BRANCH - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # Find the oldest ralph:todo issue in this milestone
  ISSUE_JSON=$(gh issue list --milestone "$MILESTONE" --label "ralph:todo" --sort created --json number,title,body --limit 1 2>/dev/null || echo "[]")
  ISSUE_NUMBER=$(echo "$ISSUE_JSON" | jq -r '.[0].number // empty')

  if [[ -z "$ISSUE_NUMBER" ]]; then
    # Check if there are in-progress issues (previous iteration may have failed to update)
    IN_PROGRESS=$(gh issue list --milestone "$MILESTONE" --label "ralph:in-progress" --json number --jq 'length' 2>/dev/null || echo "0")
    if [[ "$IN_PROGRESS" -gt 0 ]]; then
      echo "No ralph:todo issues, but $IN_PROGRESS still in-progress. Continuing..."
      # Reset in-progress back to todo for retry
      gh issue list --milestone "$MILESTONE" --label "ralph:in-progress" --json number --jq '.[].number' | while read -r num; do
        gh issue edit "$num" --remove-label "ralph:in-progress" --add-label "ralph:todo" 2>/dev/null || true
      done
      continue
    fi

    echo ""
    echo "Ralph completed all tasks! No remaining ralph:todo issues."
    exit 0
  fi

  ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.[0].title')
  ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.[0].body')

  echo "Working on: #$ISSUE_NUMBER - $ISSUE_TITLE"

  # Mark issue as in-progress
  gh issue edit "$ISSUE_NUMBER" --remove-label "ralph:todo" --add-label "ralph:in-progress" 2>/dev/null || true

  # Build the prompt: ralph.md instructions + issue context
  PROMPT=$(cat "$SCRIPT_DIR/ralph.md")
  PROMPT="$PROMPT

---

## Current Issue

**Issue:** #$ISSUE_NUMBER - $ISSUE_TITLE
**Branch:** $BRANCH
**Milestone:** $MILESTONE

$ISSUE_BODY"

  # Run Claude Code with the prompt
  OUTPUT=$(echo "$PROMPT" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS)."
echo "Check milestone progress: gh issue list --milestone \"$MILESTONE\""
exit 1
