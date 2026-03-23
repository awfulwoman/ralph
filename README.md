# Ralph

![Ralph](ralph.png)

Ralph is an autonomous AI agent loop that runs AI coding tools repeatedly until all GitHub Issues in a milestone are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and GitHub issue comments.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI](https://cli.github.com) (`gh`) installed and authenticated
- A git repository with a GitHub remote

## Setup

### Option 1: Copy to your project

```bash
mkdir -p yourproject/scripts/ralph
cp ralph.sh yourproject/scripts/ralph/
cp ralph.md yourproject/scripts/ralph/
chmod +x yourproject/scripts/ralph/ralph.sh
```

### Option 2: Install skill globally

```bash
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Plugin

```bash
/plugin marketplace add awfulwoman/ralph
/plugin install ralph-skills@awfulwoman-ralph-marketplace
```

Available skill after installation:

- `/ralph` - Plan a feature and create GitHub Issues for autonomous execution

Automatically invoked when you ask Claude to: "create a prd", "plan this feature", "write stories for", "spec out".

## Workflow

### 1. Plan a Feature

Use the `/ralph` skill to plan a feature and create GitHub Issues:

```plain
/ralph plan a task priority system
```

The skill will:

1. Ask clarifying questions
2. Break the feature into right-sized stories
3. Create a GitHub milestone with goals/non-goals
4. Create issues in dependency order with `ralph:todo` labels

### 2. Run Ralph

```bash
./scripts/ralph/ralph.sh --milestone task-priority
```

Default is 10 iterations. Ralph will:

1. Create/checkout branch `ralph/<milestone-name>`
2. Pick the oldest `ralph:todo` issue
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit with message `feat: #<issue> - <title>`
6. Update issue label to `ralph:done`, post a progress comment
7. Append learnings to `progress.txt`
8. Repeat until all issues are done or max iterations reached

## Labels

Ralph uses these labels (auto-created on first run):

| Label                | Color  | Meaning              |
|----------------------|--------|----------------------|
| `ralph:todo`         | Purple | Story not started    |
| `ralph:in-progress`  | Yellow | Agent working on it  |
| `ralph:done`         | Green  | Story completed      |
| `ralph:failed`       | Red    | Story failed         |

## Key Files

| File               | Purpose                                                |
|--------------------|--------------------------------------------------------|
| `ralph.sh`         | Bash loop that picks issues and spawns agent instances |
| `ralph.md`         | Prompt template given to each agent instance           |
| `skills/ralph/`    | Skill for planning features and creating GitHub Issues |
| `progress.txt`     | Append-only learnings for future iterations            |
| `.claude-plugin/`  | Plugin manifest for Claude Code marketplace            |
| `flowchart/`       | Interactive visualization of how Ralph works           |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new agent instance** with clean context. The only memory between iterations is:

- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
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

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10

# See comments on a specific issue
gh issue view <number> --comments
```

## Customizing the Prompt

After copying `ralph.md` to your project, customize it:

- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
