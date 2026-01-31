# Compound Product - Agent Installation Guide

This file contains instructions for AI agents to install Compound Product into a project.

## Installation

When asked to install Compound Product, run:

```bash
./install.sh /path/to/target/project
```

Or manually:

1. Copy `scripts/` to target project's `scripts/compound/`
2. Copy skills to the appropriate location:
   - Amp: `~/.config/amp/skills/`
   - Claude Code: `~/.claude/skills/`
   - OpenCode: `~/.config/opencode/skills/`
3. Copy `config.example.json` to target project as `compound.config.json`
4. Have user customize `compound.config.json`

## Usage

### Full Pipeline (Report → PR)

```bash
./scripts/compound/auto-compound.sh
```

This:
1. Finds the latest report in `reportsDir`
2. Analyzes it to pick #1 priority
3. Creates a feature branch
4. Uses agent to create PRD
5. Uses agent to convert PRD to tasks
6. Runs the execution loop
7. Creates a PR

### Dry Run

```bash
./scripts/compound/auto-compound.sh --dry-run
```

Shows what would be done without making changes.

### Just the Loop

If you already have `prd.json`:

```bash
./scripts/compound/loop.sh [max_iterations]
```

### Using Skills

Create a PRD:
```
Load the prd skill. Create a PRD for [feature description]
```

Convert PRD to tasks:
```
Load the tasks skill. Convert [path/to/prd.md] to prd.json
```

## Configuration

`compound.config.json` in the project root:

```json
{
  "tool": "amp",
  "reportsDir": "./reports",
  "outputDir": "./scripts/compound",
  "qualityChecks": ["npm run typecheck", "npm test"],
  "maxIterations": 25,
  "branchPrefix": "compound/"
}
```

### Fields

- `tool`: "amp", "claude", or "opencode"
- `reportsDir`: Where to find report markdown files
- `outputDir`: Where prd.json and progress.txt live
- `qualityChecks`: Array of commands to run after each task
- `maxIterations`: Max loop iterations before stopping
- `branchPrefix`: Prefix for created branches

### Custom Analysis

To use a custom analysis script instead of the default:

```json
{
  "analyzeCommand": "npx tsx ./my-analyze-script.ts"
}
```

Script must output JSON with: `priority_item`, `description`, `rationale`, `acceptance_criteria`, `branch_name`

## File Structure After Install

```
your-project/
├── compound.config.json          # Your configuration
├── scripts/
│   └── compound/
│       ├── auto-compound.sh      # Full pipeline
│       ├── loop.sh               # Execution loop
│       ├── analyze-report.sh     # Report analysis (default)
│       ├── prompt.md             # Amp prompt template
│       └── CLAUDE.md             # Claude Code prompt template
└── reports/                      # Your reports go here
    └── *.md
```

## Creating Reports

The system expects markdown reports in `reportsDir`. Your report can contain:

- Metrics and KPIs
- Error logs or summaries
- User feedback
- Recommendations

The AI will analyze it and pick the #1 actionable item that:
- Does NOT require database migrations
- Is completable in a few hours
- Is specific and verifiable

## Quality Requirements

Before marking any task complete, the loop runs all `qualityChecks`. If any fail, the agent must fix the issues before proceeding.

Common checks:
- `npm run typecheck` - TypeScript type checking
- `npm test` - Run test suite
- `npm run lint` - Linting
- `cargo check` - Rust type checking
- `go build` - Go compilation

## Updating AGENTS.md

When implementing tasks, update relevant AGENTS.md files with:
- Discovered patterns
- Gotchas and non-obvious requirements
- Dependencies between files
- Configuration requirements

This creates long-term memory for future agents and developers.
