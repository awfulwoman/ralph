# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs an agent repeatedly until all GitHub Issues in a milestone are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run Ralph
./scripts/ralph.sh --milestone <name> [--iterations <n>]
```

## Key Files

- `scripts/ralph.sh` - The bash loop that picks issues and spawns fresh agent instances
- `scripts/ralph.md` - Instructions given to each agent instance
- `CLAUDE.md` - Project-level instructions
- `skills/ralph/SKILL.md` - Skill for planning features and creating GitHub Issues

## How It Works

1. Use the `/ralph-github` skill to plan a feature → creates a GitHub milestone + issues
2. Run `./scripts/ralph.sh --milestone <name>` to start the loop
3. Each iteration passes all todo issues to the agent, which chooses the best one to work on
4. Loop ends when all issues are done

## Labels

- `ralph:todo` — story not started
- `ralph:in-progress` — agent is working on it
- `ralph:done` — story completed
- `ralph:failed` — story failed

## Versioning

When modifying `scripts/ralph.sh`, always update the `RALPH_VERSION` variable (near the top of the file) to the current date/time in `YYYY.MM.DD.HHMM` format using the Europe/Berlin timezone. You MUST run `TZ='Europe/Berlin' date '+%Y.%m.%d.%H%M'` to get the actual time — never guess or make up the value.

## Patterns

- Each iteration spawns a fresh agent instance with clean context
- Memory persists via git history, `scripts/progress.txt`, and GitHub issue comments
- Stories should be small enough to complete in one context window
- Progress is tracked via GitHub milestone completion percentage
