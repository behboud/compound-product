# Compound Product

A self-improving product system that reads daily reports, identifies the #1 actionable priority, and autonomously implements it.

**The concept:** Your product generates reports about its performance. An AI agent analyzes those reports, picks the most impactful fix, creates a plan, and implements it—all while you sleep. You wake up to a PR ready for review.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/) and [Ryan Carson's implementation](https://x.com/ryancarson/status/2008548371712135632).

## How It Works

```mermaid
flowchart TD
    subgraph Input
        R[📊 Daily Report<br/>metrics, errors, feedback]
    end
    
    subgraph "Phase 1: Analysis"
        A[analyze-report.sh<br/>Anthropic API]
        R --> A
        A --> J[analysis.json<br/>priority + criteria]
    end
    
    subgraph "Phase 2: Planning"
        B[Create Branch<br/>compound/feature-name]
        J --> B
        B --> PRD[AI Agent<br/>Load prd skill]
        PRD --> MD[tasks/prd-feature.md]
        MD --> TASKS[AI Agent<br/>Load tasks skill]
        TASKS --> JSON[prd.json<br/>executable tasks]
    end
    
    subgraph "Phase 3: Execution Loop"
        LOOP[loop.sh<br/>max N iterations]
        JSON --> LOOP
        LOOP --> PICK[Pick next task<br/>where passes: false]
        PICK --> IMPL[AI Agent<br/>Implement task]
        IMPL --> CHECK{Quality<br/>Checks?}
        CHECK -->|Pass| COMMIT[Git Commit]
        CHECK -->|Fail| FIX[Fix & Retry]
        FIX --> CHECK
        COMMIT --> UPDATE[Update prd.json<br/>passes: true]
        UPDATE --> DONE{All tasks<br/>done?}
        DONE -->|No| PICK
        DONE -->|Yes| EXIT[Exit loop]
    end
    
    subgraph Output
        EXIT --> PUSH[Git Push]
        PUSH --> PR[🎉 Pull Request<br/>Ready for review]
    end
```

## Quick Start

### Prerequisites

- [Amp CLI](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `jq` installed (`brew install jq` on macOS)
- `gh` CLI installed and authenticated (`brew install gh`)
- `ANTHROPIC_API_KEY` environment variable set

### Installation

```bash
# Clone the repo
git clone https://github.com/snarktank/compound-product.git
cd compound-product

# Run the installer
./install.sh /path/to/your/project
```

Or tell your AI agent:
```
Install compound-product from https://github.com/snarktank/compound-product
```

### Configuration

Copy and customize the config:

```bash
cp config.example.json config.json
```

Edit `config.json`:

```json
{
  "tool": "amp",
  "reportsDir": "./reports",
  "outputDir": "./compound",
  "qualityChecks": ["npm run typecheck", "npm test"],
  "maxIterations": 25,
  "branchPrefix": "compound/"
}
```

### Running

```bash
# Dry run - see what it would do
./scripts/compound/auto-compound.sh --dry-run

# Full run
./scripts/compound/auto-compound.sh

# Just run the loop (if you already have prd.json)
./scripts/compound/loop.sh 10
```

## Report Format

Your report can be any markdown file. The AI will analyze it and pick the #1 actionable item.

Example report structure:

```markdown
# Daily Report - 2024-01-15

## Key Metrics
- Signups: 45 (down 20% from yesterday)
- Errors: 12 TypeErrors in checkout flow
- User feedback: "Can't find the save button"

## Issues
1. Checkout flow has JavaScript errors
2. Save button is below the fold on mobile
3. Email validation is too strict

## Recommendations
- Fix checkout JavaScript errors (blocking revenue)
- Move save button above fold
- Relax email validation
```

## The Loop

Each iteration of the loop:

1. **Reads** `prd.json` to find the next task where `passes: false`
2. **Implements** the task
3. **Runs quality checks** (configurable in `config.json`)
4. **Commits** if checks pass
5. **Updates** `prd.json` to mark task as `passes: true`
6. **Appends** learnings to `progress.txt`
7. **Repeats** until all tasks complete or max iterations reached

### Memory Between Iterations

Each iteration runs with fresh context. Memory persists via:

- **Git history** - Previous commits show what was done
- **progress.txt** - Learnings and patterns discovered
- **prd.json** - Which tasks are complete
- **AGENTS.md** - Long-term codebase knowledge (updated by agents)

## Skills

Two skills are included for PRD creation and task generation:

### PRD Skill

Creates a Product Requirements Document from a feature description.

```
Load the prd skill. Create a PRD for [your feature]
```

### Tasks Skill

Converts a PRD markdown file to `prd.json` for the loop.

```
Load the tasks skill. Convert tasks/prd-feature.md to prd.json
```

## Customization

### Custom Analysis Script

By default, `analyze-report.sh` uses the Anthropic API directly. To use your own:

```json
{
  "analyzeCommand": "npx tsx ./my-custom-analyze.ts"
}
```

Your script must output JSON to stdout:

```json
{
  "priority_item": "Fix checkout errors",
  "description": "...",
  "rationale": "...",
  "acceptance_criteria": ["...", "..."],
  "branch_name": "compound/fix-checkout-errors"
}
```

### Quality Checks

Configure your project's quality checks:

```json
{
  "qualityChecks": [
    "npm run typecheck",
    "npm run lint",
    "npm test"
  ]
}
```

### Branch Prefix

All branches are created with a prefix:

```json
{
  "branchPrefix": "compound/"
}
```

## Philosophy

**Compound Product** is based on the idea that each improvement should make future improvements easier:

1. **Agents update AGENTS.md** - Discovered patterns are documented for future iterations
2. **Progress is logged** - Each task records what was learned
3. **Small tasks compound** - Many small, correct changes beat large, risky ones
4. **Human review remains** - The loop creates PRs, not direct merges

## Troubleshooting

### Loop exits early

Check `progress.txt` for errors. Common issues:

- Quality checks failing (fix the code or adjust checks)
- Task too large (split into smaller tasks)
- Context overflow (task description needs to be more focused)

### Analysis fails

Ensure `ANTHROPIC_API_KEY` is set:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

### Agent can't find tools

For Amp, ensure skills are installed:

```bash
ls ~/.config/amp/skills/
```

For Claude Code:

```bash
ls ~/.claude/skills/
```

## Contributing

PRs welcome! Please keep changes focused and include tests where applicable.

## License

MIT
