#!/bin/bash
# Compound Product - Full Pipeline
# Reads a report, picks #1 priority, creates PRD + tasks, runs loop, creates PR
#
# Usage: ./auto-compound.sh [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/compound.config.json"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2; exit 1; }

# Load config
[ -f "$CONFIG_FILE" ] || error "Config file not found: $CONFIG_FILE"

TOOL=$(jq -r '.tool // "amp"' "$CONFIG_FILE")
REPORTS_DIR="$PROJECT_ROOT/$(jq -r '.reportsDir // "./reports"' "$CONFIG_FILE")"
OUTPUT_DIR="$PROJECT_ROOT/$(jq -r '.outputDir // "./scripts/compound"' "$CONFIG_FILE")"
MAX_ITERATIONS=$(jq -r '.maxIterations // 25' "$CONFIG_FILE")
BRANCH_PREFIX=$(jq -r '.branchPrefix // "compound/"' "$CONFIG_FILE")
ANALYZE_COMMAND=$(jq -r '.analyzeCommand // ""' "$CONFIG_FILE")

TASKS_DIR="$PROJECT_ROOT/tasks"

# Check requirements
command -v "$TOOL" >/dev/null 2>&1 || error "$TOOL CLI not found"
command -v gh >/dev/null 2>&1 || error "gh CLI not found"
command -v jq >/dev/null 2>&1 || error "jq not found"

cd "$PROJECT_ROOT"
[ -f ".env.local" ] && source .env.local

# Step 1: Find most recent report
log "Step 1: Finding most recent report..."
git pull origin main 2>/dev/null || true

LATEST_REPORT=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1)
[ -f "$LATEST_REPORT" ] || error "No reports found in $REPORTS_DIR"
REPORT_NAME=$(basename "$LATEST_REPORT")
log "Using report: $REPORT_NAME"

# Step 2: Analyze report
log "Step 2: Analyzing report..."

if [ -n "$ANALYZE_COMMAND" ]; then
  ANALYSIS_JSON=$(bash -c "$ANALYZE_COMMAND \"$LATEST_REPORT\"" 2>/dev/null)
else
  ANALYSIS_JSON=$("$SCRIPT_DIR/analyze-report.sh" "$LATEST_REPORT" 2>/dev/null)
fi

[ -n "$ANALYSIS_JSON" ] || error "Failed to analyze report"

PRIORITY_ITEM=$(echo "$ANALYSIS_JSON" | jq -r '.priority_item // empty')
DESCRIPTION=$(echo "$ANALYSIS_JSON" | jq -r '.description // empty')
RATIONALE=$(echo "$ANALYSIS_JSON" | jq -r '.rationale // empty')
BRANCH_NAME=$(echo "$ANALYSIS_JSON" | jq -r '.branch_name // empty')

[ -n "$PRIORITY_ITEM" ] || error "Failed to parse priority item"

# Ensure branch has correct prefix
[[ "$BRANCH_NAME" == "$BRANCH_PREFIX"* ]] || BRANCH_NAME="${BRANCH_PREFIX}${BRANCH_NAME#*/}"

log "Priority item: $PRIORITY_ITEM"
log "Branch: $BRANCH_NAME"

[ "$DRY_RUN" = true ] && echo "$ANALYSIS_JSON" | jq . && exit 0

# Helper to run tool with prompt
run_tool() {
  local prompt="$1"
  local logfile="$2"
  case "$TOOL" in
    amp) echo "$prompt" | amp --execute --dangerously-allow-all 2>&1 | tee "$logfile" ;;
    claude) echo "$prompt" | claude --dangerously-skip-permissions 2>&1 | tee "$logfile" ;;
    opencode) echo "$prompt" | opencode run 2>&1 | tee "$logfile" ;;
  esac
}

# Step 3: Create feature branch
log "Step 3: Creating feature branch..."
git checkout main
git checkout -b "$BRANCH_NAME" || git checkout "$BRANCH_NAME"

# Step 4: Use agent to create PRD
log "Step 4: Creating PRD..."

PRD_FILENAME="prd-${BRANCH_NAME#$BRANCH_PREFIX}.md"
mkdir -p "$TASKS_DIR"

ACCEPTANCE_CRITERIA=$(echo "$ANALYSIS_JSON" | jq -r '.acceptance_criteria[]' | sed 's/^/- /')

PRD_PROMPT="Load the prd skill. Create a PRD for: $PRIORITY_ITEM

Description: $DESCRIPTION

Rationale: $RATIONALE

Acceptance criteria:
$ACCEPTANCE_CRITERIA

CONSTRAINTS:
- NO database migrations
- Scope: 2-4 hours of work
- 3-5 small, verifiable tasks
- DO NOT ask questions - proceed immediately

Save PRD to: tasks/$PRD_FILENAME"

run_tool "$PRD_PROMPT" "$OUTPUT_DIR/auto-compound-prd.log"

PRD_PATH="$TASKS_DIR/$PRD_FILENAME"
[ -f "$PRD_PATH" ] || error "PRD was not created at $PRD_PATH"
log "PRD created: $PRD_PATH"

# Archive previous run
PRD_FILE="$OUTPUT_DIR/prd.json"
PROGRESS_FILE="$OUTPUT_DIR/progress.txt"
ARCHIVE_DIR="$OUTPUT_DIR/archive"

if [ -f "$PRD_FILE" ]; then
  OLD_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_BRANCH" ] && [ "$OLD_BRANCH" != "$BRANCH_NAME" ]; then
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$(date +%Y-%m-%d)-${OLD_BRANCH#*/}"
    mkdir -p "$ARCHIVE_FOLDER"
    cp "$PRD_FILE" "$PROGRESS_FILE" "$ARCHIVE_FOLDER/" 2>/dev/null || true
    log "Archived previous run to: $ARCHIVE_FOLDER"
  fi
fi

# Step 5: Convert PRD to tasks
log "Step 5: Converting PRD to tasks..."

TASKS_PROMPT="Load the tasks skill. Convert $PRD_PATH to $OUTPUT_DIR/prd.json
Use branch name: $BRANCH_NAME
Each task must be completable in one iteration."

run_tool "$TASKS_PROMPT" "$OUTPUT_DIR/auto-compound-tasks.log"

[ -f "$OUTPUT_DIR/prd.json" ] || error "prd.json was not created"
log "Tasks: $(jq '.tasks | length' "$OUTPUT_DIR/prd.json")"

# Commit PRD and tasks
git add "$PRD_PATH" "$OUTPUT_DIR/prd.json"
git commit -m "chore: add PRD and tasks for $PRIORITY_ITEM" || true

# Step 6: Run execution loop
log "Step 6: Running loop (max $MAX_ITERATIONS iterations)..."
"$SCRIPT_DIR/loop.sh" "$MAX_ITERATIONS" 2>&1 | tee "$OUTPUT_DIR/auto-compound-execution.log"

# Step 7: Create PR
log "Step 7: Creating PR..."

git push -u origin "$BRANCH_NAME"

PR_BODY="## Compound Product: $PRIORITY_ITEM

**From report:** $REPORT_NAME

**Rationale:** $RATIONALE

### Progress
\`\`\`
$(tail -50 "$OUTPUT_DIR/progress.txt")
\`\`\`

### Tasks
\`\`\`json
$(jq '.tasks[] | {id, title, passes}' "$OUTPUT_DIR/prd.json")
\`\`\`"

PR_URL=$(gh pr create --title "Compound: $PRIORITY_ITEM" --body "$PR_BODY" --base main --head "$BRANCH_NAME")

log "✅ Complete! PR: $PR_URL"
