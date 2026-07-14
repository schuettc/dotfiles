#!/bin/bash
# Claude Code Status Line.
#
# Runs once per Claude turn. Three responsibilities:
#   1. Print the status line shown at the bottom of the Claude UI
#      (model · context % · folder). Git status is intentionally omitted
#      — tmux already shows branch + dirty count and the duplication was
#      noisy and prone to drift.
#   2. Write a per-pane state file so tmux's status-right can show the
#      current context % for the focused Claude pane. The file is keyed
#      by the inherited TMUX_PANE env var; bin/tmux-claude-context.sh
#      reads it from the tmux side.
#   3. Sync a custom Claude session name (/rename) into the tmux
#      session's @claude_task label so it shows on every surface.

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

# ─── Sync Claude session name → tmux task label ──────────────────────
# Claude ships `session_name` in the statusline JSON whenever the session
# has a name — both an explicit /rename and the auto-generated topic name
# (e.g. "Debug tmux title …") land here. Copy it into the session-scoped
# @claude_task option — the same label `prefix T` sets — so it shows in
# status-left, Ghostty tab titles, and the proj picker automatically.
#
# Manual wins: `prefix T` raises @claude_task_manual when you set a label
# by hand, and this sync backs off while that flag is present so it can't
# clobber your title every turn. Clearing the label (empty prefix T) drops
# the flag and hands the label back to Claude's auto-name.
# Plain `tmux` + inherited $TMUX reaches the right per-project server.
SESSION_NAME=$(echo "$input" | jq -r '.session_name // ""')
if [[ -n "$SESSION_NAME" && -n "${TMUX_PANE:-}" ]]; then
  is_manual=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task_manual 2>/dev/null)
  current_label=$(tmux show-option -qv -t "$TMUX_PANE" @claude_task 2>/dev/null)
  if [[ -z "$is_manual" && "$SESSION_NAME" != "$current_label" ]]; then
    tmux set-option -t "$TMUX_PANE" @claude_task "$SESSION_NAME" 2>/dev/null
    tmux refresh-client -S 2>/dev/null
  fi
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
