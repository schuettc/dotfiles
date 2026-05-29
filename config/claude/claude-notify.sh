#!/bin/bash
# Claude Code hook dispatcher — bridges Claude Code events to macOS,
# Ghostty, and tmux. Replaces the cmux-specific cmux-notify.sh.
#
# Hooks wired (see ~/.claude/settings.json):
#   Notification  → macOS notification + tmux pane bell (urgent: input needed)
#   Stop          → tmux pane bell only (quiet: turn finished)
#   SessionStart  → set tmux pane title to "claude" (visibility)
#   SessionEnd    → clear tmux pane title (visibility)
#
# Hook input is a JSON blob on stdin. The `hook_name` field selects the
# branch below.

set -u

# Read the hook payload off stdin.
input=$(cat)
# Claude Code sends the event under `hook_event_name`. Accept the older
# `hook_name` too, just in case.
hook_name=$(printf '%s' "$input" | jq -r '.hook_event_name // .hook_name // ""' 2>/dev/null || echo "")

# ─── Helpers ───────────────────────────────────────────────────────────

# Ring the tmux pane bell by writing BEL to the pane's tty. tmux's
# monitor-bell setting (configured in ~/.tmux.conf) turns this into a
# visual indicator in the window list.
ring_tmux_bell() {
  [[ -z "${TMUX_PANE:-}" ]] && return 0
  local pty
  pty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null) || return 0
  [[ -n "$pty" ]] && printf '\a' >> "$pty" 2>/dev/null || true
}

# Set / clear the tmux pane title so `tmux ls -F '#{pane_title}'` and
# the status bar can show where Claude is running.
set_pane_title() {
  [[ -z "${TMUX_PANE:-}" ]] && return 0
  tmux select-pane -t "$TMUX_PANE" -T "${1:-}" 2>/dev/null || true
}

# ─── Dispatch ──────────────────────────────────────────────────────────
# Both Notification and Stop just ring the tmux pane bell. tmux's
# monitor-bell turns that into the status-left attention banner
# (bin/tmux-attention.sh) + the window-status indicator, and Ghostty
# adds a 🔔 to the tab title + a pane border flash (bell-features).
# No macOS notification, no Dock bounce — purely in-terminal cues.

case "$hook_name" in
  Notification|Stop)
    ring_tmux_bell
    ;;

  SessionStart|SessionEnd)
    # No-op: Claude Code sets its own pane title via OSC 2 ("✳ Claude
    # Code"). Trying to set it from a hook is a race we lose because
    # Claude re-emits the title on every render.
    :
    ;;
esac

exit 0
