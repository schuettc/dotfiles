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

# Write session mapping for cmux workspace
if [[ -n "$CMUX_WORKSPACE_ID" ]]; then
  echo "$SESSION_ID" > ~/.claude/sessions/cmux-${CMUX_WORKSPACE_ID}.session
fi

# Read feature name if set
FEATURE=""
if [[ -f ~/.claude/sessions/${SESSION_ID}.feature ]]; then
  FEATURE=$(cat ~/.claude/sessions/${SESSION_ID}.feature)
fi

# Get git info
GIT_BRANCH=""
GIT_MODIFIED=0
GIT_STAGED=0
GIT_UNTRACKED=0
GIT_AHEAD=0
GIT_BEHIND=0
GIT_STASHES=0
GIT_CONFLICTS=0

if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_BRANCH=$(git branch --show-current 2>/dev/null)

  # Get file status counts using porcelain format for reliability
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    xy="${line:0:2}"
    case "$xy" in
      "??") ((GIT_UNTRACKED++)) ;;
      "UU"|"AA"|"DD"|"AU"|"UA"|"DU"|"UD") ((GIT_CONFLICTS++)) ;;
      *)
        # First char = staged status, second = unstaged
        [[ "${xy:0:1}" != " " && "${xy:0:1}" != "?" ]] && ((GIT_STAGED++))
        [[ "${xy:1:1}" != " " && "${xy:1:1}" != "?" ]] && ((GIT_MODIFIED++))
        ;;
    esac
  done < <(git status --porcelain 2>/dev/null)

  # Get ahead/behind counts
  UPSTREAM=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [[ -n "$UPSTREAM" ]]; then
    AHEAD_BEHIND=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    GIT_AHEAD=$(echo "$AHEAD_BEHIND" | cut -f1)
    GIT_BEHIND=$(echo "$AHEAD_BEHIND" | cut -f2)
  fi

  # Get stash count
  GIT_STASHES=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
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

# Git info
if [[ -n "$GIT_BRANCH" ]]; then
  GIT_PARTS=("🌿 $GIT_BRANCH")

  # Ahead/behind remote
  if [[ "$GIT_AHEAD" -gt 0 || "$GIT_BEHIND" -gt 0 ]]; then
    SYNC=""
    [[ "$GIT_AHEAD" -gt 0 ]] && SYNC+="↑$GIT_AHEAD"
    [[ "$GIT_BEHIND" -gt 0 ]] && SYNC+="↓$GIT_BEHIND"
    GIT_PARTS+=("$SYNC")
  fi

  # Conflicts (show prominently if any)
  if [[ "$GIT_CONFLICTS" -gt 0 ]]; then
    GIT_PARTS+=("⚠️ ${GIT_CONFLICTS} conflicts")
  fi

  # File changes: staged, modified, untracked
  CHANGES=""
  [[ "$GIT_STAGED" -gt 0 ]] && CHANGES+="●$GIT_STAGED "
  [[ "$GIT_MODIFIED" -gt 0 ]] && CHANGES+="✚$GIT_MODIFIED "
  [[ "$GIT_UNTRACKED" -gt 0 ]] && CHANGES+="…$GIT_UNTRACKED"
  CHANGES=$(echo "$CHANGES" | sed 's/ $//')
  [[ -n "$CHANGES" ]] && GIT_PARTS+=("$CHANGES")

  # Stashes
  if [[ "$GIT_STASHES" -gt 0 ]]; then
    GIT_PARTS+=("📦$GIT_STASHES")
  fi

  # Join git parts with spaces
  PARTS+=("${GIT_PARTS[*]}")
fi

# Push context to cmux sidebar
if [[ -n "$CMUX_SOCKET_PATH" ]]; then
  LABEL="${FEATURE:-$MODEL}"
  if [[ "$CONTEXT_PCT" -gt 80 ]]; then
    COLOR="#f38ba8"  # red
  elif [[ "$CONTEXT_PCT" -gt 50 ]]; then
    COLOR="#f9e2af"  # yellow
  else
    COLOR="#a6e3a1"  # green
  fi
  cmux set-status "claude" "${LABEL} · ${CONTEXT_PCT}%" --color "$COLOR" 2>/dev/null &
fi

# Join with separator
printf '%s' "${PARTS[0]}"
for part in "${PARTS[@]:1}"; do
  printf ' │ %s' "$part"
done
echo
