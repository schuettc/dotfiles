#!/bin/bash
# Claude Code Status Line.
#
# Runs once per Claude turn. Two responsibilities:
#   1. Print the status line shown at the bottom of the Claude UI
#      (model · context % · folder). Git status is intentionally omitted
#      — tmux already shows branch + dirty count and the duplication was
#      noisy and prone to drift.
#   2. Write a per-pane state file so tmux's status-right can show the
#      current context % for the focused Claude pane. The file is keyed
#      by the inherited TMUX_PANE env var; bin/tmux-claude-context.sh
#      reads it from the tmux side.

input=$(cat)

# ─── Parse JSON ──────────────────────────────────────────────────────
MODEL=$(echo "$input"        | jq -r '.model.display_name // "Claude"')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
CURRENT_DIR=$(echo "$input"  | jq -r '.workspace.current_dir // ""')

# Calculate context usage percentage.
CONTEXT_PCT=0
if [[ "$CONTEXT_SIZE" -gt 0 ]] 2>/dev/null && [[ "$INPUT_TOKENS" -gt 0 ]] 2>/dev/null; then
  CONTEXT_PCT=$((INPUT_TOKENS * 100 / CONTEXT_SIZE))
fi

FOLDER_NAME=""
[[ -n "$CURRENT_DIR" ]] && FOLDER_NAME=$(basename "$CURRENT_DIR")

# Optional feature label (legacy hook from feature-workflow).
FEATURE=""
[[ -f ~/.claude/feature-context ]] && FEATURE=$(cat ~/.claude/feature-context)

# ─── Write state file for tmux status bar ────────────────────────────
# Keyed by TMUX_PANE so multiple Claude sessions don't clobber each other.
# Sanitized for the filesystem (TMUX_PANE looks like "%47").
if [[ -n "${TMUX_PANE:-}" ]]; then
  state_dir="${TMPDIR:-/tmp}/claude-status"
  mkdir -p "$state_dir" 2>/dev/null
  state_key="${TMUX_PANE//[^a-zA-Z0-9]/_}"
  printf 'context_pct=%d\nmodel=%s\nupdated=%d\n' \
    "$CONTEXT_PCT" "$MODEL" "$(date +%s)" \
    > "$state_dir/$state_key" 2>/dev/null
fi

# ─── Build the in-Claude status line ─────────────────────────────────
PARTS=()

if [[ -n "$FEATURE" ]]; then
  PARTS+=("💡 $FEATURE")
else
  PARTS+=("🤖 $MODEL")
fi

if [[ "$CONTEXT_PCT" -gt 0 ]]; then
  if   [[ "$CONTEXT_PCT" -gt 80 ]]; then PARTS+=("🔴 ${CONTEXT_PCT}%")
  elif [[ "$CONTEXT_PCT" -gt 50 ]]; then PARTS+=("🟡 ${CONTEXT_PCT}%")
  else                                    PARTS+=("🟢 ${CONTEXT_PCT}%")
  fi
fi

[[ -n "$FOLDER_NAME" ]] && PARTS+=("📂 $FOLDER_NAME")

# Print with " │ " separators.
printf '%s' "${PARTS[0]}"
for part in "${PARTS[@]:1}"; do
  printf ' │ %s' "$part"
done
echo
