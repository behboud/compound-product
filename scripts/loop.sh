#!/bin/bash
# Compound Product - Execution Loop
# Runs AI agent repeatedly until all tasks complete.
#
# Usage: ./loop.sh [--tool amp|claude|opencode] [max_iterations]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/compound.config.json"

  # Load config
  if [ -f "$CONFIG_FILE" ]; then
    TOOL=$(jq -r '.tool // "amp"' "$CONFIG_FILE")
    MODEL=$(jq -r '.model // "opencode/minimax-m2.1-free"' "$CONFIG_FILE")
    OUTPUT_DIR="$PROJECT_ROOT/$(jq -r '.outputDir // "./scripts/compound"' "$CONFIG_FILE")"
    MAX_ITERATIONS=$(jq -r '.maxIterations // 10' "$CONFIG_FILE")
  else
    TOOL="amp"
    MODEL="opencode/minimax-m2.1-free"
    OUTPUT_DIR="$PROJECT_ROOT/scripts/compound"
    MAX_ITERATIONS=10
  fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tool|--tool=*) 
      [[ "$1" == --tool=* ]] && TOOL="${1#*=}" || { TOOL="$2"; shift; }
      shift ;;
    [0-9]*) MAX_ITERATIONS="$1"; shift ;;
    *) shift ;;
  esac
done

PRD_FILE="$OUTPUT_DIR/prd.json"
PROGRESS_FILE="$OUTPUT_DIR/progress.txt"

# Initialize progress file
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Compound Product Progress Log
Started: $(date)
---" > "$PROGRESS_FILE"
fi

# Helper to run tool
run_tool() {
  case "$TOOL" in
    amp) cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 ;;
    claude) claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 ;;
    opencode) opencode run --model "$MODEL" "$(cat "$SCRIPT_DIR/prompt.md")" 2>&1 ;;
    *) echo "Error: Unknown tool '$TOOL'" >&2; exit 1 ;;
  esac
}

echo "Starting Compound Loop - Tool: $TOOL - Model: $MODEL - Max: $MAX_ITERATIONS"
cd "$PROJECT_ROOT"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "
================================================
  Iteration $i of $MAX_ITERATIONS
================================================"

  OUTPUT=$(run_tool | tee /dev/stderr) || true

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo "
✅ All tasks complete! Finished at iteration $i"
    exit 0
  fi

  sleep 2
done

echo "
⚠️  Reached max iterations ($MAX_ITERATIONS)"
exit 1
