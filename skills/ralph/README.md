# /ralph Skill

Plan a feature, break it into right-sized stories, and create GitHub Issues for autonomous execution by Ralph.

## What It Does

1. Asks 3-5 clarifying questions (with lettered options for quick answers like "1A, 2C, 3B")
2. Breaks the feature into small, dependency-ordered stories
3. Creates a GitHub milestone with goals/non-goals
4. Creates issues in execution order with `ralph:todo` labels

## Usage

```plain
/ralph plan a notification system
```

Also triggers when you say: "create a prd", "plan this feature", "write stories for", "spec out".

## Story Design Principles

- Each story must be completable in one Ralph iteration (one context window)
- Stories are ordered by dependency: schema -> backend -> UI
- Every story has verifiable acceptance criteria (not vague)
- All stories include "Typecheck passes"; UI stories include browser verification

## Installation

```bash
cp -r skills/ralph ~/.claude/skills/
```
