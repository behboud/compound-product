#!/bin/bash
# Analyze a report and pick #1 actionable priority
# Uses the AI client configured in compound.config.json
#
# Usage: ./analyze-report.sh <report-path>
# Output: JSON to stdout

set -e

REPORT_PATH="$1"

if [ -z "$REPORT_PATH" ]; then
  echo "Usage: ./analyze-report.sh <report-path>" >&2
  exit 1
fi

if [ ! -f "$REPORT_PATH" ]; then
  echo "Error: Report file not found: $REPORT_PATH" >&2
  exit 1
fi

# Find project root and config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/compound.config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: compound.config.json not found at $CONFIG_FILE" >&2
  exit 1
fi

# Read configured tool from config
TOOL=$(jq -r '.tool // "amp"' "$CONFIG_FILE")

# Map tool to command
get_tool_command() {
  case "$1" in
    amp)
      echo "amp"
      ;;
    claude|claude-code)
      echo "claude"
      ;;
    opencode)
      echo "opencode"
      ;;
    *)
      echo "amp"
      ;;
  esac
}

TOOL_CMD=$(get_tool_command "$TOOL")

# Check if tool is available
if ! command -v "$TOOL_CMD" &> /dev/null; then
  echo "Error: Configured tool '$TOOL' (command: $TOOL_CMD) is not installed or not in PATH" >&2
  echo "Please install $TOOL or update compound.config.json" >&2
  exit 1
fi

REPORT_CONTENT=$(cat "$REPORT_PATH")

# Find recent PRDs (last 7 days) to avoid re-picking same issues
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASKS_DIR="$PROJECT_ROOT/tasks"
RECENT_FIXES=""

if [ -d "$TASKS_DIR" ]; then
  # Find prd-*.md files modified in last 7 days
  RECENT_PRDS=$(find "$TASKS_DIR" -name "prd-*.md" -mtime -7 2>/dev/null || true)
  if [ -n "$RECENT_PRDS" ]; then
    RECENT_FIXES="
## Recently Fixed (Last 7 Days) - DO NOT PICK THESE AGAIN
"
    for prd in $RECENT_PRDS; do
      # Extract title from first heading
      TITLE=$(grep -m1 "^# " "$prd" 2>/dev/null | sed 's/^# //' || basename "$prd" .md)
      DATE=$(stat -f "%Sm" -t "%Y-%m-%d" "$prd" 2>/dev/null || stat -c "%y" "$prd" 2>/dev/null | cut -d' ' -f1)
      RECENT_FIXES="$RECENT_FIXES- $DATE: $TITLE
"
    done
  fi
fi

PROMPT="You are analyzing a daily report for a software product.

Read this report and identify the #1 most actionable item that should be worked on TODAY.

CONSTRAINTS:
- Must NOT require database migrations (no schema changes)
- Must be completable in a few hours of focused work
- Must be a clear, specific task (not vague like 'improve conversion')
- Prefer fixes over new features
- Prefer high-impact, low-effort items
- Focus on UI/UX improvements, copy changes, bug fixes, or configuration changes
- IMPORTANT: Do NOT pick items that appear in the 'Recently Fixed' section below
$RECENT_FIXES
REPORT:
$REPORT_CONTENT

Respond with ONLY a JSON object (no markdown, no code fences, no explanation):
{
  \"priority_item\": \"Brief title of the item\",
  \"description\": \"2-3 sentence description of what needs to be done\",
  \"rationale\": \"Why this is the #1 priority based on the report\",
  \"acceptance_criteria\": [\"List of 3-5 specific, verifiable criteria\"],
  \"estimated_tasks\": 3,
  \"branch_name\": \"compound/kebab-case-feature-name\"
}"

# Use the configured tool to analyze the report
# Create a temp file for the prompt
PROMPT_FILE=$(mktemp)
echo "$PROMPT" > "$PROMPT_FILE"

# Call the tool with the prompt
case "$TOOL_CMD" in
  amp)
    TEXT=$($TOOL_CMD --no-tty -p "$PROMPT_FILE" 2>/dev/null || true)
    ;;
  claude)
    TEXT=$($TOOL_CMD -p "$PROMPT" 2>/dev/null || true)
    ;;
  opencode)
    TEXT=$($TOOL_CMD run --no-interactive -p "$PROMPT" 2>/dev/null || true)
    ;;
  *)
    echo "Error: Unknown tool command: $TOOL_CMD" >&2
    rm "$PROMPT_FILE"
    exit 1
    ;;
esac

rm "$PROMPT_FILE"

if [ -z "$TEXT" ]; then
  echo "Error: Failed to get response from $TOOL" >&2
  exit 1
fi

# Try to parse as JSON, handle potential markdown wrapping
if echo "$TEXT" | jq . >/dev/null 2>&1; then
  echo "$TEXT" | jq .
else
  # Try to extract JSON from markdown code block
  JSON_EXTRACTED=$(echo "$TEXT" | sed -n '/^{/,/^}/p' | head -20)
  if echo "$JSON_EXTRACTED" | jq . >/dev/null 2>&1; then
    echo "$JSON_EXTRACTED" | jq .
  else
    echo "Error: Could not parse response as JSON" >&2
    echo "Response text: $TEXT" >&2
    exit 1
  fi
fi
