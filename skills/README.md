# Skills

Claude Code skills that ship with Ralph.

## Available Skills

| Skill | Description |
|-------|-------------|
| [`ralph-github`](ralph/) | Plan a feature and create GitHub Issues for autonomous execution by Ralph |

## Installation

Copy skills to your global agent config:

```bash
cp -r ralph ~/.claude/skills/ # Claude as an example
```

Or install via the Claude Code plugin marketplace:

```bash
/plugin marketplace add awfulwoman/ralph
/plugin install awful-ralph@awfulwoman-ralph-marketplace
```

## Usage

Invoke the skill in your agent:

```plain
/ralph-github plan a task priority system
```

Also triggers automatically when you say: "create a prd", "plan this feature", "write stories for", "spec out".
