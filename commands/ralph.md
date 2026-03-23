---
description: "Plan a feature and create GitHub Issues for Ralph autonomous execution"
allowed-tools: Bash(gh:*)
---

# Ralph PRD & Issue Creator

Plan a feature, break it into right-sized stories, and create GitHub Issues for autonomous execution by Ralph.

## Steps

1. Ask 3-5 clarifying questions with lettered options (so user can reply "1A, 2C, 3B")
2. Break feature into small stories — each completable in one agent iteration
3. Create a GitHub milestone + issues via `gh` CLI

**Do NOT implement anything. Only create the milestone and issues.**

## Story Rules

- Each story must fit in one context window (2-3 sentences to describe the change)
- Order by dependency: schema → backend → UI
- Every story needs verifiable acceptance criteria + "Typecheck passes"
- UI stories add "Verify in browser using dev-browser skill"

## Create via gh CLI

```bash
# Milestone
gh api repos/{owner}/{repo}/milestones -f title="<name>" -f description="<goals, non-goals>"

# Labels (idempotent)
gh label create "ralph:todo" --color "5319E7" --description "Story not started" --force
gh label create "ralph:in-progress" --color "FBCA04" --description "Agent working on story" --force
gh label create "ralph:done" --color "0E8A16" --description "Story completed" --force
gh label create "ralph:failed" --color "D93F0B" --description "Story failed" --force

# Issues (creation order = execution order)
gh issue create --title "<title>" --body "<body>" --milestone "<name>" --label "ralph:todo"
```

## Issue body format

```markdown
As a [user], I want [feature] so that [benefit].

## Acceptance Criteria
- [ ] Specific verifiable criterion
- [ ] Typecheck passes
```
