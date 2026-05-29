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

# Show a macOS notification (Notification Center). Uses osascript so no
# external dependencies are required.
macos_notify() {
  local title="$1" body="$2"
  # Escape double quotes for AppleScript string literals.
  title=${title//\"/\\\"}
  body=${body//\"/\\\"}
  osascript -e "display notification \"$body\" with title \"$title\" sound name \"Funk\"" \
    >/dev/null 2>&1 || true
}

# ─── Dispatch ──────────────────────────────────────────────────────────

case "$hook_name" in
  Notification)
    # Payload shape: { message, notification_type, cwd, ... }
    body=$(printf '%s' "$input" | jq -r '.message // "Claude needs your attention"')
    cwd=$(printf '%s'  "$input" | jq -r '.cwd // ""')
    proj=$(basename "$cwd" 2>/dev/null)
    title="Claude · ${proj:-Code}"
    macos_notify "$title" "$body"
    ring_tmux_bell
    ;;

  Stop)
    # Quiet: just ring the pane bell so the window indicator lights up,
    # but no popup (every turn would be noisy).
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
