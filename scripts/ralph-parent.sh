#!/bin/bash
# Ralph — parent mode
#
# Works through the open sub-issues of one parent issue, across repos.
# State lives on a GitHub Project board, not in labels:
#
#   Ready + Agent-ready=Yes  → eligible (todo)
#   In Progress              → claimed by an agent
#   Blocked                  → the agent could not finish
#   closed                   → done (the board moves it on, e.g. to Merged)
#
# Each sub-issue's repo is expected at <workspace>/<repo> and is cloned there
# if missing. Agents commit to main with `Fixes owner/repo#n` and push.
#
# Usage: ./scripts/ralph-parent.sh --parent <owner/repo#n | issue URL> --project <n>
#          [--project-owner <login>] [--workspace <dir>] [--iterations <n>]
#          [--model <model>] [--dry-run] [--verbose]

set -e

# ── Parse arguments ──────────────────────────────────────────────

PARENT=""
PROJECT_NUMBER=""
PROJECT_OWNER=""
WORKSPACE=""
MAX_ITERATIONS=10
MODEL="claude-sonnet-4-6"
VERBOSE=false
DRY_RUN=false
TOOL_COMMAND="claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Board field and option names. Override with environment variables.
STATUS_FIELD="${RALPH_STATUS_FIELD:-Status}"
AGENT_FIELD="${RALPH_AGENT_FIELD:-Agent-ready}"
READY="${RALPH_READY:-Ready}"
IN_PROGRESS="${RALPH_IN_PROGRESS:-In Progress}"
BLOCKED="${RALPH_BLOCKED:-Blocked}"
AGENT_YES="${RALPH_AGENT_YES:-Yes}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose|-v)      VERBOSE=true;               shift   ;;
    --dry-run)         DRY_RUN=true;               shift   ;;
    --parent)          PARENT="$2";                shift 2 ;;
    --parent=*)        PARENT="${1#*=}";           shift   ;;
    --project)         PROJECT_NUMBER="$2";        shift 2 ;;
    --project=*)       PROJECT_NUMBER="${1#*=}";   shift   ;;
    --project-owner)   PROJECT_OWNER="$2";         shift 2 ;;
    --project-owner=*) PROJECT_OWNER="${1#*=}";    shift   ;;
    --workspace)       WORKSPACE="$2";             shift 2 ;;
    --workspace=*)     WORKSPACE="${1#*=}";        shift   ;;
    --iterations)      MAX_ITERATIONS="$2";        shift 2 ;;
    --iterations=*)    MAX_ITERATIONS="${1#*=}";   shift   ;;
    --model)           MODEL="$2";                 shift 2 ;;
    --model=*)         MODEL="${1#*=}";            shift   ;;
    *)                 shift ;;
  esac
done

# ── Preflight checks ────────────────────────────────────────────

for cmd in gh jq git; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd not found."
    exit 1
  fi
done

if [[ -z "$PARENT" || -z "$PROJECT_NUMBER" ]]; then
  echo "Error: --parent and --project are required."
  echo "Usage: $0 --parent owner/repo#n --project <n> [--workspace <dir>]"
  exit 1
fi

# Accept owner/repo#n or https://github.com/owner/repo/issues/n
if [[ "$PARENT" =~ ^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
  PARENT_OWNER="${BASH_REMATCH[1]}"; PARENT_REPO="${BASH_REMATCH[2]}"; PARENT_NUMBER="${BASH_REMATCH[3]}"
elif [[ "$PARENT" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
  PARENT_OWNER="${BASH_REMATCH[1]}"; PARENT_REPO="${BASH_REMATCH[2]}"; PARENT_NUMBER="${BASH_REMATCH[3]}"
else
  echo "Error: --parent must be owner/repo#n or an issue URL, got: $PARENT"
  exit 1
fi
PROJECT_OWNER="${PROJECT_OWNER:-$PARENT_OWNER}"

# Default workspace: the parent of the current repo, or the current dir.
if [[ -z "$WORKSPACE" ]]; then
  if TOP=$(git rev-parse --show-toplevel 2>/dev/null); then
    WORKSPACE="$(dirname "$TOP")"
  else
    WORKSPACE="$(pwd)"
  fi
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

SLUG="${PARENT_OWNER}-${PARENT_REPO}-${PARENT_NUMBER}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ralph"
PROGRESS_FILE="$STATE_DIR/$SLUG.md"
mkdir -p "$STATE_DIR"

# ── Resolve the board ───────────────────────────────────────────

PROJECT_JSON=$(gh api graphql -f owner="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" -f query='
query($owner: String!, $number: Int!) {
  repositoryOwner(login: $owner) {
    ... on User { projectV2(number: $number) { ...P } }
    ... on Organization { projectV2(number: $number) { ...P } }
  }
}
fragment P on ProjectV2 {
  id title
  fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } } }
}' --jq '.data.repositoryOwner.projectV2')

if [[ -z "$PROJECT_JSON" || "$PROJECT_JSON" == "null" ]]; then
  echo "Error: project $PROJECT_OWNER/$PROJECT_NUMBER not found (gh needs the 'project' scope)."
  exit 1
fi

PROJECT_ID=$(echo "$PROJECT_JSON" | jq -r '.id')
PROJECT_TITLE=$(echo "$PROJECT_JSON" | jq -r '.title')

field_id()  { echo "$PROJECT_JSON" | jq -r --arg f "$1" '.fields.nodes[] | select(.name == $f) | .id'; }
option_id() { echo "$PROJECT_JSON" | jq -r --arg f "$1" --arg o "$2" \
  '.fields.nodes[] | select(.name == $f) | .options[] | select(.name == $o) | .id'; }

STATUS_FIELD_ID=$(field_id "$STATUS_FIELD")
IN_PROGRESS_ID=$(option_id "$STATUS_FIELD" "$IN_PROGRESS")
BLOCKED_ID=$(option_id "$STATUS_FIELD" "$BLOCKED")
READY_ID=$(option_id "$STATUS_FIELD" "$READY")

for v in STATUS_FIELD_ID IN_PROGRESS_ID BLOCKED_ID READY_ID; do
  if [[ -z "${!v}" ]]; then
    echo "Error: project '$PROJECT_TITLE' is missing field '$STATUS_FIELD' or one of its options ($READY, $IN_PROGRESS, $BLOCKED)."
    exit 1
  fi
done
if [[ -z "$(field_id "$AGENT_FIELD")" ]]; then
  echo "Error: project '$PROJECT_TITLE' has no '$AGENT_FIELD' field."
  exit 1
fi

# ── Helper: fetch sub-issues with their board state ─────────────
# Prints a JSON array, one object per sub-issue.

fetch_sub_issues() {
  gh api graphql -f owner="$PARENT_OWNER" -f repo="$PARENT_REPO" -F number="$PARENT_NUMBER" \
    -f status="$STATUS_FIELD" -f agent="$AGENT_FIELD" -f query='
query($owner: String!, $repo: String!, $number: Int!, $status: String!, $agent: String!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      subIssues(first: 100) {
        nodes {
          number title body state url
          repository { name nameWithOwner }
          projectItems(first: 20) {
            nodes {
              id project { id }
              status: fieldValueByName(name: $status) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
              agent: fieldValueByName(name: $agent) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            }
          }
        }
      }
    }
  }
}' | jq --arg project "$PROJECT_ID" '
  [.data.repository.issue.subIssues.nodes[]
   | (.projectItems.nodes | map(select(.project.id == $project)) | first) as $item
   | {number, title, body, state, url,
      repo: .repository.name, nameWithOwner: .repository.nameWithOwner,
      item: ($item.id // null), status: ($item.status.name // null), agent: ($item.agent.name // null)}]'
}

# ── Helper: make sure a repo is cloned, clean and up to date ────
# Returns non-zero (and says why) if the repo cannot be used this iteration.

prepare_repo() {
  local name_with_owner="$1" repo="$2" dir="$WORKSPACE/$2"
  if [[ ! -d "$dir/.git" ]]; then
    echo "  Cloning $name_with_owner into $dir"
    $DRY_RUN && return 0
    gh repo clone "$name_with_owner" "$dir" -- --quiet || { echo "  Skip $repo: clone failed"; return 1; }
  fi
  local default
  default=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  default="${default:-main}"
  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    echo "  Skip $repo: working tree is dirty"; return 1
  fi
  if [[ "$(git -C "$dir" branch --show-current)" != "$default" ]]; then
    echo "  Skip $repo: not on $default"; return 1
  fi
  $DRY_RUN && return 0
  git -C "$dir" pull --ff-only --quiet || { echo "  Skip $repo: cannot fast-forward $default"; return 1; }
}

# ── Initialize progress file ────────────────────────────────────

if [[ ! -f "$PROGRESS_FILE" ]]; then
  {
    echo "# Ralph Progress Log"
    echo "Parent: $PARENT_OWNER/$PARENT_REPO#$PARENT_NUMBER"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
fi

# ── Report ──────────────────────────────────────────────────────

print_summary() {
  echo "$1" | jq -r --arg ready "$READY" --arg yes "$AGENT_YES" '.[] |
    (if .state == "CLOSED" then "[x]"
     elif .status == $ready and .agent == $yes then "[ ]"
     else "[-]" end)
    + " \(.nameWithOwner)#\(.number) \(.title)  (\(.status // "not on board")\(if .agent then ", agent-ready: " + .agent else "" end))"' \
    | sed 's/^/  /'
  echo "  ([x] closed, [ ] eligible, [-] waiting on a human or another status)"
}

echo "==============================================================="
echo "  Ralph (parent mode)"
echo "  Parent:     $PARENT_OWNER/$PARENT_REPO#$PARENT_NUMBER"
echo "  Board:      $PROJECT_TITLE ($PROJECT_OWNER #$PROJECT_NUMBER)"
echo "  Workspace:  $WORKSPACE"
echo "  Model:      $MODEL"
echo "  Iterations: $MAX_ITERATIONS"
echo "  Progress:   $PROGRESS_FILE"
$DRY_RUN && echo "  DRY RUN — no agent is spawned, nothing is changed"
echo "==============================================================="

# ── Main loop ────────────────────────────────────────────────────

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  SUBS=$(fetch_sub_issues)
  $VERBOSE && echo "  Sub-issues: $SUBS"
  print_summary "$SUBS"

  ELIGIBLE=$(echo "$SUBS" | jq --arg ready "$READY" --arg yes "$AGENT_YES" \
    '[.[] | select(.state == "OPEN" and .item != null and .status == $ready and .agent == $yes)]')

  # Drop sub-issues whose repo is not usable right now.
  USABLE="[]"
  for nwo in $(echo "$ELIGIBLE" | jq -r '[.[].nameWithOwner] | unique | .[]'); do
    if prepare_repo "$nwo" "${nwo#*/}"; then
      USABLE=$(echo "$USABLE" "$ELIGIBLE" | jq -s --arg nwo "$nwo" '.[0] + [.[1][] | select(.nameWithOwner == $nwo)]')
    fi
  done

  COUNT=$(echo "$USABLE" | jq 'length')
  if [[ "$COUNT" -eq 0 ]]; then
    OPEN=$(echo "$SUBS" | jq '[.[] | select(.state == "OPEN")] | length')
    echo ""
    if [[ "$OPEN" -eq 0 ]]; then
      echo "All sub-issues of $PARENT_OWNER/$PARENT_REPO#$PARENT_NUMBER are closed."
      if ! $DRY_RUN; then
        gh issue comment "$PARENT_NUMBER" -R "$PARENT_OWNER/$PARENT_REPO" \
          --body "Ralph: all sub-issues are closed. Verify the deploy, then close this parent." >/dev/null || true
      fi
    else
      echo "Nothing eligible: $OPEN open sub-issue(s) need a human (not Ready + $AGENT_FIELD=$AGENT_YES, or repo not usable)."
    fi
    exit 0
  fi

  echo "$COUNT eligible sub-issue(s) — agent will choose which to work on"

  # Build prompt: ralph-parent.md instructions + board IDs + eligible issues
  PROMPT_FILE=$(mktemp)
  trap "rm -f '$PROMPT_FILE'" EXIT
  cat "$SCRIPT_DIR/ralph-parent.md" > "$PROMPT_FILE"
  cat >> "$PROMPT_FILE" <<CONTEXT_EOF

---

## Run Context

- **Parent issue:** $PARENT_OWNER/$PARENT_REPO#$PARENT_NUMBER
- **Workspace:** $WORKSPACE (each repo is at \`$WORKSPACE/<repo>\`)
- **Progress file:** $PROGRESS_FILE
- **Host:** $(hostname)

### Board IDs

- Project ID: \`$PROJECT_ID\`
- Status field ID: \`$STATUS_FIELD_ID\`
- Status options: In Progress \`$IN_PROGRESS_ID\`, Blocked \`$BLOCKED_ID\`, Ready \`$READY_ID\`

### Closed Sub-issues
$(echo "$SUBS" | jq -r '.[] | select(.state == "CLOSED") | "- [x] \(.nameWithOwner)#\(.number) \(.title)"')

### Eligible Sub-issues (pick one)
$(echo "$USABLE" | jq -r --arg ws "$WORKSPACE" '.[] |
  "---\n#### \(.nameWithOwner)#\(.number) \(.title)\n- Repo path: `\($ws)/\(.repo)`\n- Board item ID: `\(.item)`\n- URL: \(.url)\n\n\(.body)\n"')
CONTEXT_EOF

  if $DRY_RUN; then
    echo ""
    echo "Dry run: prompt for this iteration is below."
    echo "---------------------------------------------------------------"
    cat "$PROMPT_FILE"
    rm -f "$PROMPT_FILE"
    exit 0
  fi

  # Spawn a fresh Claude Code instance from the workspace
  TOOL_ARGS="--dangerously-skip-permissions --print --model $MODEL"
  $VERBOSE && echo "  Spawning: (cd $WORKSPACE && $TOOL_COMMAND $TOOL_ARGS < $PROMPT_FILE)"
  OUTPUT=$(cd "$WORKSPACE" && $TOOL_COMMAND $TOOL_ARGS < "$PROMPT_FILE" 2>&1 | tee /dev/stderr) || true
  rm -f "$PROMPT_FILE"

  WORKING_ON=$(echo "$OUTPUT" | grep -m1 "RALPH_WORKING_ON:" | sed 's/.*RALPH_WORKING_ON:[[:space:]]*//' || true)
  if [[ -n "$WORKING_ON" ]]; then
    echo ""
    echo "---------------------------------------------------------------"
    echo "  Agent worked on: $WORKING_ON"
    echo "---------------------------------------------------------------"
  fi
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS)."
exit 1
