# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs an agent repeatedly until all GitHub Issues in a milestone are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph
./scripts/ralph.sh --milestone <name> [max_iterations]
```

## Key Files

- `scripts/ralph.sh` - The bash loop that picks issues and spawns fresh agent instances
- `scripts/ralph.md` - Instructions given to each agent instance
- `CLAUDE.md` - Project-level instructions
- `skills/ralph/SKILL.md` - Skill for planning features and creating GitHub Issues
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## How It Works

1. Use the `/ralph-github` skill to plan a feature → creates a GitHub milestone + issues
2. Run `./scripts/ralph.sh --milestone <name>` to start the loop
3. Each iteration picks the oldest `ralph:todo` issue, implements it, updates labels
4. Loop ends when all issues are done

## Labels

- `ralph:todo` — story not started
- `ralph:in-progress` — agent is working on it
- `ralph:done` — story completed
- `ralph:failed` — story failed

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Versioning

When modifying `scripts/ralph.sh`, always update the `RALPH_VERSION` variable (near the top of the file) to the current date/time in `YYYY.MM.DD.HHMM` format using the Europe/Berlin timezone.

## Patterns

- Each iteration spawns a fresh agent instance with clean context
- Memory persists via git history, `progress.txt`, and GitHub issue comments
- Stories should be small enough to complete in one context window
- Progress is tracked via GitHub milestone completion percentage
