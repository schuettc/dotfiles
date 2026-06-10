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
# Claude pre-computes the cumulative context-window usage percentage in
# `.context_window.used_percentage`. (Don't compute from
# `current_usage.input_tokens` — that's only the *new* tokens this turn,
# typically 1–2 due to prompt caching.)
MODEL=$(echo "$input"        | jq -r '.model.display_name // "Claude"')
CONTEXT_PCT=$(echo "$input"  | jq -r '.context_window.used_percentage // 0')
CURRENT_DIR=$(echo "$input"  | jq -r '.workspace.current_dir // ""')

FOLDER_NAME=""
[[ -n "$CURRENT_DIR" ]] && FOLDER_NAME=$(basename "$CURRENT_DIR")

# Optional feature label (legacy hook from feature-workflow).
FEATURE=""
[[ -f ~/.claude/feature-context ]] && FEATURE=$(cat ~/.claude/feature-context)

# ─── Write state file for tmux status bar ────────────────────────────
# Keyed by TMUX_PANE so multiple Claude sessions don't clobber each other.
# Sanitized for the filesystem (TMUX_PANE looks like "%47").
if [[ -n "${TMUX_PANE:-}" ]]; then
  state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
  mkdir -p "$state_dir" 2>/dev/null
  state_key="${TMUX_PANE//[^a-zA-Z0-9]/_}"
  printf 'context_pct=%d\nmodel=%s\nupdated=%d\n' \
    "$CONTEXT_PCT" "$MODEL" "$(date +%s)" \
    > "$state_dir/$state_key" 2>/dev/null
fi

# ─── Print the in-Claude status line ─────────────────────────────────
# Inside tmux: print NOTHING. Model + context% are shown in tmux's
# status-right (bin/tmux-claude-context.sh reads the state file written
# above). An empty line here can't overflow the pane width, so it can't
# leave the wrapped-status redraw residue Claude's TUI produces under tmux.
#
# Outside tmux there's no status bar to carry it, so fall back to a lean,
# ASCII-only label (no width-2 emoji) — model (or feature) · folder.
if [[ -z "${TMUX_PANE:-}" ]]; then
  if [[ -n "$FEATURE" ]]; then
    printf '%s' "$FEATURE"
  else
    printf '%s' "$MODEL"
  fi
  [[ -n "$FOLDER_NAME" ]] && printf ' · %s' "$FOLDER_NAME"
  echo
fi
