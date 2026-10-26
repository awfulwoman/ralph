# Ralph for Claude Code and GitHub

![Ralph](assets/ralph.png)

Ralph is an autonomous [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agent loop that runs Claude repeatedly until a set of GitHub Issues is complete. Each iteration is a fresh instance with clean context. Memory persists via git history and GitHub issue comments.

It has two modes:

- **Parent mode** — works through the sub-issues of one parent issue, across any number of repos. State lives on a GitHub Project board (`Status` + `Agent-ready` fields). Agents commit straight to each repo's default branch.
- **Milestone mode** — works through one milestone in the current repo. State lives in `ralph:*` labels. Work lands on a `ralph/<milestone>` branch and a PR.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI](https://cli.github.com) (`gh`) installed and authenticated
- A git repository with a GitHub remote

## Setup

### Install the Ralph script and prompt to your projct

```bash
curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash

# Install into a specific directory (instead of ./scripts/)
curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash -s -- --dir bin
```

<details>
<summary>Or install script manually</summary>

```bash
mkdir -p yourproject/scripts
cp scripts/ralph.sh scripts/ralph.md scripts/ralph-parent.sh scripts/ralph-parent.md yourproject/scripts/
```

</details>

### Install Skills

```bash
/plugin marketplace add awfulwoman/ralph
/plugin install awful-ralph@awfulwoman-ralph-marketplace
```

<details>
<summary>Or install skills manually</summary>

```bash
cp -r skills/ralph ~/.claude/skills/
```

</details>

## Skills

The following skill will be available after installation:

- `/ralph-github` - Plan a feature and create GitHub Issues for autonomous execution

EXCEPT THAT IT WON'T BE AVAIALBLE because there's some kind of bug in Claude Code that stops the `/ralph-github` command from working. Instead you can invoke it when you ask your agent to: "create a prd", "plan this feature", "write stories for", "spec out".

Look, don't blame me.

## Workflow

### 1. Plan a Feature

Use the `/ralph-github` skill to plan a feature and create GitHub Issues:

```plain
/ralph-github plan a task priority system
```

The skill will:

1. Ask clarifying questions
2. Break the feature into right-sized stories
3. Parent mode: create a parent issue with goals/non-goals, then sub-issues in the repos they change, linked to the parent, on the board and set to Ready
4. Milestone mode: create a milestone with goals/non-goals, then issues in dependency order with `ralph:todo` labels

### 2a. Run Ralph — parent mode

Needs a GitHub Project with a single-select `Status` field (with `Ready`, `In Progress` and `Blocked` options) and a single-select `Agent-ready` field (`Yes`/`No`). `gh` needs the `project` scope (`gh auth refresh -s project`).

```bash
./scripts/ralph.sh --parent <owner/repo#n | issue URL> --project <number>

# Examples:
./scripts/ralph.sh --parent awfulwoman/meta#15 --project 4
./scripts/ralph.sh --parent awfulwoman/meta#15 --project 4 --dry-run          # show what it would do
./scripts/ralph.sh --parent awfulwoman/meta#15 --project 4 --workspace ~/Code # repos live in ~/Code/<repo>
./scripts/ralph.sh --parent acme/plans#7 --project 2 --project-owner acme-org
```

- **Eligible:** open sub-issues with Status `Ready` and Agent-ready `Yes`. Nothing else is touched, so a human controls what an agent may do.
- **Workspace:** each sub-issue's repo is expected at `<workspace>/<repo>`; it is cloned there if missing. The default workspace is the parent of the current repo, or the current directory if it is not a repo. A repo with a dirty tree, or not on its default branch, is skipped.
- **Each iteration:** the agent picks one sub-issue, sets it In Progress with a claim comment, implements it, runs the repo's checks, commits with `Fixes owner/repo#n`, and pushes. On failure it sets Blocked and says why. It never sets Done — that is for whoever verifies the deploy.
- **Progress log:** `~/.local/state/ralph/<owner>-<repo>-<n>.md` (outside the repos).
- **Field names** can be changed with `RALPH_STATUS_FIELD`, `RALPH_AGENT_FIELD`, `RALPH_READY`, `RALPH_IN_PROGRESS`, `RALPH_BLOCKED` and `RALPH_AGENT_YES`.

Ralph stops when nothing is eligible (all closed, or the rest need a human) or max iterations is reached. When every sub-issue is closed it comments on the parent.

### 2b. Run Ralph — milestone mode

```bash
./scripts/ralph.sh --milestone <milestone-name>

# Examples:
./scripts/ralph.sh --milestone task-priority                 # default 10 iterations
./scripts/ralph.sh --milestone task-priority --iterations 20 # up to 20 iterations
./scripts/ralph.sh                                           # auto-picks oldest incomplete milestone
./scripts/ralph.sh --model claude-opus-4-6                  # use a different model
./scripts/ralph.sh --verbose                                 # verbose output
./scripts/ralph.sh --auto-merge                              # merge PR and pull to local main when complete
```

If `--milestone` is omitted, Ralph finds the oldest open milestone that still has `ralph:todo` issues and runs that. This makes it easy to run multiple milestones in sequence.

Each iteration, Ralph will:

1. Choose the best `ralph:todo` issue from the milestone to work on
2. Spawn a fresh agent instance to implement it
3. Run quality checks (typecheck, tests)
4. Commit, mark the issue `ralph:done`, and move on

Ralph stops when all issues are done or max iterations is reached.

## Labels

In milestone mode, Ralph uses these labels (auto-created on first run):

| Label                | Color  | Meaning              |
|----------------------|--------|----------------------|
| `ralph:todo`         | Purple | Story not started    |
| `ralph:in-progress`  | Yellow | Agent working on it  |
| `ralph:done`         | Green  | Story completed      |
| `ralph:failed`       | Red    | Story failed         |

## Key Files

| File               | Purpose                                                |
|--------------------|--------------------------------------------------------|
| `scripts/ralph.sh` | Bash loop that picks issues and spawns agent instances (milestone mode; hands `--parent` runs to `ralph-parent.sh`) |
| `scripts/ralph.md` | Prompt template given to each agent instance (milestone mode) |
| `scripts/ralph-parent.sh` | Parent-mode loop: sub-issues across repos, state on a Project board |
| `scripts/ralph-parent.md` | Prompt template given to each agent instance (parent mode) |
| `skills/ralph/`    | Skill for planning features and creating GitHub Issues |
| `.claude-plugin/`  | Plugin manifest for Claude Code marketplace            |

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new agent instance** with clean context. The only memory between iterations is:

- Git history (commits from previous iterations)
- GitHub issue comments (what each iteration did)
- GitHub milestone (which stories are done via labels)

### Small Tasks

Each issue should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:

- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):

- "Build a dashboard"
- "Add authentication"
- "Refactor the API"

### Feedback Loops

Ralph only works if there are feedback loops:

- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When no `ralph:todo` issues remain in the milestone, Ralph exits successfully.

## Debugging

```bash
# See milestone progress
gh issue list --milestone "<name>" --json number,title,labels --jq '.[] | {number, title, status: .labels[].name}'

# Check git history
git log --oneline -10

# See comments on a specific issue
gh issue view <number> --comments
```

## Customising the Prompt

After copying `scripts/ralph.md` to your project, customise it:

- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Development

These commands are for maintaining the Ralph repository itself.

### `/release`

Bumps the plugin version, commits, and pushes. Increments the minor version by default, or accepts an explicit version:

```plain
/release          # e.g. 1.10.0 → 1.11.0
/release 2.0.0    # explicit version
```

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
