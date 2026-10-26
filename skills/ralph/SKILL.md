---
name: ralph
description: "Plan a feature and create GitHub Issues (a parent issue with sub-issues across repos on a Project board, or a single-repo milestone) for Ralph autonomous execution. Use when planning a feature, starting a new project, or creating stories for Ralph. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out, convert this prd, ralph."
user-invocable: true
---

# Ralph PRD & Issue Creator

Plan a feature, break it into right-sized stories, and create GitHub Issues for autonomous execution by Ralph.

---

## The Job

1. Receive a feature description from the user
2. Ask 3-5 essential clarifying questions (with lettered options)
3. Generate right-sized user stories
4. Create a parent issue + sub-issues (possibly across repos) on a GitHub
   Project board via `gh` CLI — or, for a single-repo run, a milestone + issues

**Important:** Do NOT start implementing. Just create the issues.

---

## Step 1: Clarifying Questions

Ask only critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

### Format Questions Like This:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

This lets users respond with "1A, 2C, 3B" for quick iteration. Remember to indent the options.

---

## Step 1.5: Delegate PRD Generation to Specialist Agent

After receiving the user's answers, spawn a specialist agent using the Agent tool with `model: "opus"` to produce the PRD and stories. Pass it:
- The original feature description
- All clarifying Q&A
- The full content of this skill (story sizing rules, ordering rules, acceptance criteria rules, example)

The specialist agent should return:
- Parent (or milestone) title and description
- Ordered list of stories with titles, target repo, user story sentences, and acceptance criteria

Use its output verbatim for Step 3. Do not redesign or re-summarize the stories yourself.

---

## Step 2: Story Design

Design user stories following these rules.

### Story Size: The Number One Rule

**Each story must be completable in ONE Ralph iteration (one context window).**

Ralph spawns a fresh agent instance per iteration with no memory of previous work. If a story is too big, the LLM runs out of context before finishing and produces broken code.

#### Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

#### Too big (split these):
- "Build the entire dashboard" → split into: schema, queries, UI components, filters
- "Add authentication" → split into: schema, middleware, login UI, session handling
- "Refactor the API" → split into one story per endpoint or pattern

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, it is too big.

### Story Ordering: Dependencies First

Issues are created in dependency order, and each agent picks the next story by reading the dependencies. So creation order should match execution order, and a story that depends on another should say so ("Depends on owner/repo#n").

**Correct order:**
1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views that aggregate data

**Wrong order:**
1. UI component (depends on schema that does not exist yet)
2. Schema change

### Acceptance Criteria: Must Be Verifiable

Each criterion must be something the agent can CHECK, not something vague.

#### Good criteria (verifiable):
- "Add `status` column to tasks table with default 'pending'"
- "Filter dropdown has options: All, Active, Completed"
- "Clicking delete shows confirmation dialog"
- "Typecheck passes"
- "Tests pass"

#### Bad criteria (vague):
- "Works correctly"
- "User can do X easily"
- "Good UX"
- "Handles edge cases"

#### Always include as final criterion:
```
Typecheck passes
```

For stories with testable logic, also include:
```
Tests pass
```

For stories that change UI, also include:
```
Verify in browser using dev-browser skill
```

---

## Step 3: Create the Issues

Use `gh` CLI to create everything. Run these commands in sequence.

**Important:** Always write issue bodies to a temp file and use `--body-file`
instead of `--body`. This avoids Claude Code permission warnings about quoted
newlines with `#`-prefixed lines.

Ask which mode to use if it is not clear:

- **Parent mode (default)** — stories can be in different repos. State lives on
  a GitHub Project board with a `Status` field (`Ready`, `In Progress`,
  `Blocked`, …) and an `Agent-ready` field (`Yes`/`No`). Run with
  `ralph.sh --parent owner/repo#n --project <n>`.
- **Milestone mode** — all stories in the current repo, tracked with
  `ralph:*` labels. Run with `ralph.sh --milestone <name>`.

### Parent mode

#### Create the parent issue

The parent body holds the PRD context: goals, non-goals, success metrics,
technical considerations, and a link to a spec if there is one.

```bash
cat > /tmp/parent-body.md << 'ISSUE_EOF'
<goals, non-goals, technical context, link to spec>
ISSUE_EOF

PARENT_URL=$(gh issue create -R <owner/repo> --title "<feature name>" --body-file /tmp/parent-body.md)
gh project item-add <project-number> --owner <owner> --url "$PARENT_URL"
```

#### Create each sub-issue, in dependency order

Create each story **in the repo whose code it changes**. Start the body with
`Part of <owner/repo>#<parent>.`

```bash
cat > /tmp/issue-body.md << 'ISSUE_EOF'
Part of <owner/repo>#<parent>.

As a [user], I want [feature] so that [benefit].

## Acceptance Criteria
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck passes
ISSUE_EOF

URL=$(gh issue create -R <owner/story-repo> --title "<Story title>" --body-file /tmp/issue-body.md)

# Link it as a sub-issue (needs the numeric issue ID, not the number)
ID=$(gh api "repos/<owner/story-repo>/issues/${URL##*/}" --jq .id)
gh api -X POST "repos/<owner/repo>/issues/<parent>/sub_issues" -F sub_issue_id="$ID"

# Put it on the board
ITEM=$(gh project item-add <project-number> --owner <owner> --url "$URL" --format json --jq .id)
```

#### Mark stories Ready

Ralph only picks up sub-issues with **Status = Ready** and **Agent-ready =
Yes**. Get the IDs with `gh project field-list <project-number> --owner <owner>
--format json`, then:

```bash
gh project item-edit --project-id <project-id> --id "$ITEM" \
  --field-id <status-field-id> --single-select-option-id <ready-option-id>
```

Set Ready for every story. **Set Agent-ready = Yes only when the user says
so** — it means an agent may do the work without asking them anything.

### Milestone mode

#### Create the milestone

```bash
gh api repos/{owner}/{repo}/milestones -f title="<feature-name>" -f description="<goals, non-goals, technical context>"
```

The milestone description should capture the high-level PRD context: goals, non-goals, success metrics, and technical considerations. This is the only place this information lives.

#### Create labels (if they don't exist)

```bash
gh label create "ralph:todo" --color "5319E7" --description "Story not started" --force
gh label create "ralph:in-progress" --color "FBCA04" --description "Agent working on story" --force
gh label create "ralph:done" --color "0E8A16" --description "Story completed" --force
gh label create "ralph:failed" --color "D93F0B" --description "Story failed" --force
```

#### Create issues in dependency order

For each story, create an issue in the current repo.

```bash
cat > /tmp/issue-body.md << 'ISSUE_EOF'
As a [user], I want [feature] so that [benefit].

## Acceptance Criteria
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Typecheck passes
ISSUE_EOF

gh issue create \
  --title "<Story title>" \
  --body-file /tmp/issue-body.md \
  --milestone "<feature-name>" \
  --label "ralph:todo"
```

Keep it simple. The title is the story name. The body is the description + checklist. GitHub's issue number is the ID.

---

## Writing for Agents

The issue reader is an AI agent with no prior context. Therefore:

- Be explicit and unambiguous
- Avoid jargon or explain it
- Provide enough detail to understand purpose and core logic
- Use concrete examples where helpful

---

## Splitting Large PRDs

If a PRD has big features, split them:

**Original:**
> "Add user notification system"

**Split into:**
1. Add notifications table to database
2. Create notification service for sending notifications
3. Add notification bell icon to header
4. Create notification dropdown panel
5. Add mark-as-read functionality
6. Add notification preferences page

Each is one focused change that can be completed and verified independently.

---

## Example

**User asks:** "Add task status tracking"

**After Q&A, create:**

Parent issue: **Task status tracking**
> "Track task progress with status indicators. Goals: toggle status, filter by status, visual badges. Non-goals: no status history/audit log, no automated status transitions."

Sub-issues (created in this order, each starting "Part of owner/repo#<parent>."):

1. **Add status field to tasks table**
   > As a developer, I need to store task status in the database.
   > - [ ] Add status column: 'pending' | 'in_progress' | 'done' (default 'pending')
   > - [ ] Generate and run migration successfully
   > - [ ] Typecheck passes

2. **Display status badge on task cards**
   > As a user, I want to see task status at a glance.
   > - [ ] Each task card shows colored status badge
   > - [ ] Badge colors: gray=pending, blue=in_progress, green=done
   > - [ ] Typecheck passes
   > - [ ] Verify in browser using dev-browser skill

3. **Add status toggle to task list rows**
   > As a user, I want to change task status directly from the list.
   > - [ ] Each row has status dropdown or toggle
   > - [ ] Changing status saves immediately
   > - [ ] UI updates without page refresh
   > - [ ] Typecheck passes
   > - [ ] Verify in browser using dev-browser skill

4. **Filter tasks by status**
   > As a user, I want to filter the list to see only certain statuses.
   > - [ ] Filter dropdown: All | Pending | In Progress | Done
   > - [ ] Filter persists in URL params
   > - [ ] Typecheck passes
   > - [ ] Verify in browser using dev-browser skill

---

## Checklist Before Creating Issues

- [ ] Asked clarifying questions with lettered options
- [ ] Incorporated user's answers
- [ ] Each story is completable in one iteration (small enough)
- [ ] Stories are ordered by dependency (schema → backend → UI)
- [ ] Every story has "Typecheck passes" as criterion
- [ ] UI stories have "Verify in browser using dev-browser skill" as criterion
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] No story depends on a later story
- [ ] Parent (or milestone) description captures goals, non-goals, and technical context
- [ ] Parent mode: each sub-issue is in the repo it changes, linked to the parent, on the board, and Ready
- [ ] Parent mode: Agent-ready = Yes set only where the user agreed
