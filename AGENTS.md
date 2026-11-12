# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs an agent repeatedly until a set of GitHub Issues is complete. Each iteration is a fresh instance with clean context.

Two modes:

- **Parent mode** — the sub-issues of one parent issue, across repos. State on a GitHub Project board (`Status`, `Agent-ready`). Commits go to each repo's default branch.
- **Milestone mode** — one milestone in the current repo. State in `ralph:*` labels. Work goes on a branch + PR.

## Commands

```bash
# Parent mode
./scripts/ralph.sh --parent <owner/repo#n> --project <n> [--workspace <dir>] [--iterations <n>] [--dry-run]

# Milestone mode
./scripts/ralph.sh --milestone <name> [--iterations <n>]
```

## Key Files

- `scripts/ralph.sh` - Milestone-mode loop; hands `--parent` runs to `ralph-parent.sh`
- `scripts/ralph.md` - Instructions given to each agent instance (milestone mode)
- `scripts/ralph-parent.sh` - Parent-mode loop
- `scripts/ralph-parent.md` - Instructions given to each agent instance (parent mode)
- `CLAUDE.md` - Project-level instructions
- `skills/ralph/SKILL.md` - Skill for planning features and creating GitHub Issues

## How It Works

1. Use the `/ralph-github` skill to plan a feature → creates a parent issue + sub-issues on a board (or a milestone + issues)
2. Run `./scripts/ralph.sh --parent ...` (or `--milestone ...`)
3. Each iteration passes all eligible issues to the agent, which chooses the best one to work on
4. Loop ends when nothing is eligible or max iterations is reached

## Parent-mode board states

- `Ready` + `Agent-ready = Yes` — eligible
- `In Progress` — claimed by an agent (with a claim comment)
- `Blocked` — the agent could not finish (comment says why)
- closed — done; the board moves it on. Agents never set Done.

## Milestone-mode labels

- `ralph:todo` — story not started
- `ralph:in-progress` — agent is working on it
- `ralph:done` — story completed
- `ralph:failed` — story failed

## Patterns

- Each iteration spawns a fresh agent instance with clean context
- Memory persists via git history, the progress file, and GitHub issue comments
- Stories should be small enough to complete in one context window
- Test changes to `ralph-parent.sh` with `--dry-run` against a real parent issue
