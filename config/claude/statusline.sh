#!/bin/bash
# Claude Code Status Line - Feature Context + Session Info

input=$(cat)

# Parse JSON input
SESSION_ID=$(echo "$input" | jq -r '.session_id')
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')

# Calculate context usage percentage
CONTEXT_PCT=0
if [[ "$CONTEXT_SIZE" -gt 0 ]] 2>/dev/null; then
  INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
  if [[ "$INPUT_TOKENS" -gt 0 ]] 2>/dev/null; then
    CONTEXT_PCT=$((INPUT_TOKENS * 100 / CONTEXT_SIZE))
  fi
fi

# Ensure sessions directory exists
mkdir -p ~/.claude/sessions

# Write session mapping for this iTerm tab
if [[ -n "$ITERM_SESSION_ID" ]]; then
  echo "$SESSION_ID" > ~/.claude/sessions/iterm-${ITERM_SESSION_ID}.session
fi

# Read feature name if set
FEATURE=""
if [[ -f ~/.claude/sessions/${SESSION_ID}.feature ]]; then
  FEATURE=$(cat ~/.claude/sessions/${SESSION_ID}.feature)
fi

# Get git branch
GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_BRANCH=$(git branch --show-current 2>/dev/null)
fi

# Get folder name from current dir
FOLDER_NAME=""
if [[ -n "$CURRENT_DIR" ]]; then
  FOLDER_NAME=$(basename "$CURRENT_DIR")
fi

# Build status line parts
PARTS=()

# Feature or model name
if [[ -n "$FEATURE" ]]; then
  PARTS+=("💡 $FEATURE")
else
  PARTS+=("🤖 $MODEL")
fi

# Context percentage
if [[ "$CONTEXT_PCT" -gt 0 ]]; then
  if [[ "$CONTEXT_PCT" -gt 80 ]]; then
    PARTS+=("🔴 ${CONTEXT_PCT}%")
  elif [[ "$CONTEXT_PCT" -gt 50 ]]; then
    PARTS+=("🟡 ${CONTEXT_PCT}%")
  else
    PARTS+=("🟢 ${CONTEXT_PCT}%")
  fi
fi

# Working directory
if [[ -n "$FOLDER_NAME" ]]; then
  PARTS+=("📂 $FOLDER_NAME")
fi

# Git branch
if [[ -n "$GIT_BRANCH" ]]; then
  PARTS+=("🌿 $GIT_BRANCH")
fi

# Join with separator
printf '%s' "${PARTS[0]}"
for part in "${PARTS[@]:1}"; do
  printf ' │ %s' "$part"
done
echo
